require('./../core/extensions')
redis = require 'redis'
#async = require 'async'
config = require('./../../config').config

TimeExploder = require('./../core/time_exploder').TimeExploder
PathExploder = require('./../core/path_exploder').PathExploder

Event = require('./../models/event').Event
EventView = require('./../models/event_view').EventView
EventListView = require('./../models/event_list_view').EventListView
View = require('./../models/view').View
TimeSlice = require('./../models/time_slice').TimeSlice
Path = require('./../models/path').Path


class RedisKey
  @namespace = 'rats'

  @scheme: -> "#{@namespace}://"

  @path: (path) -> "#{@scheme()}#{path}"

  @metaKeys: -> @path 'meta/keys'

  @paths: (paths) -> @path(path) for path in paths


class RedisSink
  @DEPTH_TO_SEND = 2
  @redisClient = redis.createClient(config.redis.port, config.redis.host)
  @redisPoolSize = 2
  @redisConnections = []
  @eventPaths = {}

  @getConnection: () ->
    return @redisClient
    if @redisConnections.length == 0
      for i in [0..@redisPoolSize - 1]
        @redisConnections.push redis.createClient(config.redis.port, config.redis.host)

    randomConnection = Math.floor(Math.random()*@redisPoolSize)
    #console.log "random connection = #{randomConnection}"
    return @redisConnections[randomConnection]


  # returns the set of known events
  # AB todo - use the in-memory tree, rather than from redis
  @listEvents: (view, depth, listEventsCallback) ->
    currentDepth = Path.getDepth view.path

    @redisClient.zrangebyscore(RedisKey.metaKeys(), currentDepth, currentDepth + depth, (err, events) =>
      throw new Error(err) if err
      #console.log '[listEvents]', events
      # filter events based on the view path
      filteredEvents = (event for event in events when event.startsWith view.path)
      listEventsCallback(err, filteredEvents)
    )

  @getHistoricalEventData: (view, eventListViewCallback) ->
    time = new Date()
    @listEvents view, 1, (err, eventPaths) =>
      # no events, no historical data
      if eventPaths.length == 0
        eventListViewCallback(new EventListView(view, []))
        return

      paths = @getTimePaths(time, view.timeSlice, eventPaths, view.measurements)
      #console.log '[getHistoricalEventData::paths]', paths
      redisTimePaths = RedisKey.paths(paths.map (element) -> element.timePath)
      #console.log '[getHistoricalEventData::redisTimePaths]', redisTimePaths

      # get events from redis
      @redisClient.mget redisTimePaths, (err, replies) =>
        # create events from the event list
        events = []
        currentEvent = null
        currentPath = ''
        for i in [0..redisTimePaths.length-1]
          if currentPath != paths[i].path
            currentPath = paths[i].path
            currentEvent = new Event({path: paths[i].path})
            events.push currentEvent

          currentEvent.measurements.push [paths[i].time, replies[i] ? 0]

        eventListView = new EventListView(view, events)
        eventListViewCallback(eventListView)


  @getHistoricalEventData2: (view, eventViewCallback) ->
    time = new Date()
    depth = 1
    @listEvents view, depth, (err, eventPaths) =>
      if eventPaths.length == 0
        eventViewCallback(new EventView(view, new Event {}))
        return

      paths = @getTimePaths(time, view.timeSlice, eventPaths, view.measurements)
      redisTimePaths = RedisKey.paths(paths.map (element) -> element.timePath)

      @redisClient.mget redisTimePaths, (err, replies) =>
        events = []
        currentEvent = null
        currentPath = ''

        i = 0
        while i < redisTimePaths.length - 1
          i++
          if currentPath != paths[i].path
            currentPath = paths[i].path
            currentEvent = new Event({path: paths[i].path})
            events.push currentEvent

          redisCount = parseInt(replies[i] ? 0)
          currentEvent.measurements.push [paths[i].time, redisCount]

        eventTree = Event.buildTree view.path, events
        eventView = new EventView(view, eventTree)
        eventViewCallback(eventView)


  # returns an event view
  #  = new View({timeSlice: TimeSlice.ONE_MINUTE, path: Event.ROOT_PATH})
  @getRollingLiveEventData: (view, eventViewCallback) ->
    time = new Date()
    @listEvents view, RedisSink.DEPTH_TO_SEND, (err, eventPaths) =>
      if eventPaths.length == 0
        eventViewCallback(new EventView(view, new Event {}))
        return

      [smallerTimeSlice, numMeasurements] = TimeExploder.convertToSmallerTimeIncrement view.timeSlice
      # get 2 smaller measurements
      paths = @getTimePaths(time, smallerTimeSlice, eventPaths, numMeasurements*2)
#      console.log '[paths]', paths.length
      redisTimePaths = RedisKey.paths(paths.map (element) -> element.timePath)
      #console.log '[redistimepaths]', redisTimePaths

      # get events from redis
      @redisClient.mget redisTimePaths, (err, replies) =>
        #console.log err, replies
#        console.log '[redisTimePaths] length = ', replies.length
        events = []
        currentEvent = null
        currentPath = ''
        count = 0
        previousCount = 0
        batch = 1

        i = 0
        while i < redisTimePaths.length - 1
          i++

          if currentPath != paths[i].path
            currentPath = paths[i].path
            currentEvent = new Event({path: paths[i].path})
            events.push currentEvent

          # all this logic is for tallying up the current (last N measurements) and
          # tallying the previous (last [N*2..N] measurements)
          if i == batchEnd
            count = 0
            previousCount = 0
            batch += 1

          batchEnd = batch*numMeasurements*2

          redisCount = parseInt(replies[i] ? 0)
          set = ''
          if i < batchEnd - numMeasurements
            count += redisCount
            currentEvent.count = count
            set = 'count'
          else
            previousCount += redisCount
            currentEvent.previousCount = previousCount
            set = 'previous'

#          if currentPath != Event.ROOT_PATH
#            console.log '[rolling]', "i: #{i}, set: #{set}, redisCount: #{redisCount} currentPath: #{currentPath}, time: #{paths[i].time}, batch: #{batch}, count: #{count}, previous: #{previousCount}"


          currentEvent.measurements.push [paths[i].time, redisCount]

        #console.log 'here'

        eventTree = Event.buildTree view.path, events
        eventView = new EventView(view, eventTree)
        eventViewCallback(eventView)


  # returns an event view
  #  = new View({timeSlice: TimeSlice.ONE_MINUTE, path: Event.ROOT_PATH})
  @getLiveEventData: (view, eventViewCallback) ->
    console.log "[RedisSink::getLiveEventData]"
    time = new Date()
    @listEvents view, 1, (err, eventPaths) =>
      if eventPaths.length == 0
        eventViewCallback(new EventView(view, new Event {}))
        return

      measurements = 1
      paths = @getTimePaths(time, view.timeSlice, eventPaths, measurements)
      redisTimePaths = RedisKey.paths(paths.map (element) -> element.timePath)
      #console.log '[redisTimePaths]', redisTimePaths

      # get events from redis
      @redisClient.mget redisTimePaths, (err, replies) =>

        # create events from the event list
        events = []
        for i in [0..redisTimePaths.length-1]
          events.push new Event({path: paths[i].path, count: replies[i] ? 0, redisKey: redisTimePaths[i]})

        eventTree = Event.buildTree view.path, events
        eventView = new EventView(view, eventTree)
        eventViewCallback(eventView)


  # returns (path, timePath)
  # paths are an array of {path: , depth: } hashes
  @getTimePaths: (time, timeSlice, paths, measurements = 1) ->
    times = TimeExploder.explode(time, timeSlice, measurements)
    timePaths = []
    for path in paths
      for [slice, time] in times
        p = path.path ? path
        timePaths.push {
          path: p, time: time,
          timeSlice: slice,
          timePath: Path.sanitize("#{p}/#{slice}/#{time}".surround(Event.PATH_SEPARATOR))
        }
    timePaths


  @incrby: (item) ->
    RedisSink.redisClient.incrby(item[0], item[1])

  @eventCache = {}
  @useEventCache = false

  @send: (event) ->
    # todo - have a class to represent this stuff
    #bucket = event.data.b
    uid = "#{event.data.uid}"
    test = event.data.t
    testPath = event.data.tp
    funnel = event.data.f
    funnelStep = event.data.fs
    value = parseInt(event.data.v ? 1)
    paths = PathExploder.explode(event.data.e)

    # save meta, but only when we have to
    for path in paths
      if @eventPaths[path.path] == undefined
        @eventPaths[path.path] = path.depth
        @redisClient.zadd(RedisKey.metaKeys(), path.depth, path.path)


    # save increments at various time increments
    timePaths = (@getTimePaths event.time, 'all', paths).map (element) -> element.timePath

    redisTimePaths = timePaths.map (t) -> [RedisKey.path(t), value]


    #if @useEventCache
    #  console.log 'using event cache'
    #  eventEpoch = Math.floor(event.time.getTime() / 1000)
    #  nowEpoch = Math.floor(new Date().getTime() / 1000)
    #  for redisTimePath in redisTimePaths
    #    @eventCache[eventEpoch] ?= {}
    #    @eventCache[eventEpoch][redisTimePath] += value

    #  # next, iterate through it and check for any epochs less than now to flush
    #  for epoch, counters of @eventCache
    #    if epoch < nowEpoch
    #      epochTimePaths = [redisKey, redisValue] for redisKey, redisValue of counters
    #      delete @eventCache[epoch]
    #      async.forEach(redisTimePaths,  @incrby, (err) -> console.log err)

    #else
    @redisClient.incrby(RedisKey.path(timePath), value) for timePath in timePaths
      #async.forEach(redisTimePaths,  @incrby, (err) -> console.log err )


    # build the distribution numbers
#    if uid.length > 1
#      console.log "[RedisSink] uid = #{uid}"


exports.RedisSink = RedisSink

