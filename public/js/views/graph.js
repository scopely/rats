(function() {
  var Graph;
  Graph = (function() {
    function Graph() {}
    Graph.drawLineGraph = function(graphData, canvasId) {
      var colors, data, graph, keys, tooltips;
      data = graphData.data;
      tooltips = graphData.tooltips;
      keys = graphData.legend;
      colors = graphData.colors;
      if ($('#' + canvasId).length === 0) {
        return;
      }
      RGraph.Clear(document.getElementById(canvasId));
      graph = new RGraph.Line(canvasId, data);
      graph.Set('chart.title.xaxis', 'Time ' + tooltips[0] + ' ' + tooltips[tooltips.length - 1]);
      graph.Set('chart.colors', colors);
      graph.Set('chart.tickmarks', 'dot');
      graph.Set('chart.linewidth', 5);
      graph.Set('chart.tooltips', tooltips);
      graph.Set('chart.tooltips.effect', 'contract');
      graph.Set('chart.key', keys);
      graph.Set('chart.key.shadow', true);
      graph.Set('chart.key.shadow.offsetx', 0);
      graph.Set('chart.key.shadow.offsety', 0);
      graph.Set('chart.key.shadow.blur', 15);
      graph.Set('chart.key.shadow.color', '#ddd');
      graph.Set('chart.key.rounded', true);
      graph.Set('chart.key.position', 'graph');
      graph.Set('chart.key.position.x', graph.Get('chart.gutter.left') + 4);
      graph.Set('chart.key.position.y', 5);
      graph.Set('chart.text.font', "Helvetica");
      graph.Set('chart.text.size', 8);
      graph.Set('chart.text.color', "#999");
      graph.Set('chart.fillstyle', "#00c176");
      graph.Set('chart.tickmarks', "square");
      return graph.Draw();
    };
    Graph.drawBarGraph = function(graphData, canvasId) {
      var colors, data, graph, keys, tooltips;
      data = graphData.data;
      tooltips = graphData.tooltips;
      keys = graphData.legend;
      colors = graphData.colors;
      if ($('#' + canvasId).length === 0) {
        return;
      }
      RGraph.Clear(document.getElementById(canvasId));
      graph = new RGraph.HBar(canvasId, data);
      graph.Set('chart.strokestyle', 'rgba(0,0,0,0)');
      graph.Set('chart.gutter.left', 275);
      graph.Set('chart.gutter.right', 10);
      graph.Set('chart.background.grid.autofit', true);
      graph.Set('chart.title', keys);
      graph.Set('chart.labels', tooltips);
      graph.Set('chart.shadow', true);
      graph.Set('chart.shadow.color', 'gray');
      graph.Set('chart.shadow.offsetx', 0);
      graph.Set('chart.shadow.offsety', 0);
      graph.Set('chart.shadow.blur', 15);
      graph.Set('chart.colors', ['red']);
      graph.Set('chart.text.font', "Helvetica");
      graph.Set('chart.text.size', 8);
      return graph.Draw();
    };
    return Graph;
  })();
  window.Graph = Graph;
}).call(this);
