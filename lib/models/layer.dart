class Layer {
  final String name;
  final String title;
  final String url;
  final String workspace;
  final List<double>? boundingBox;

  Layer({
    required this.name,
    required this.title,
    required this.url,
    required this.workspace,
    this.boundingBox,
  });

  factory Layer.fromXml(dynamic layerElement, String baseUrl) {
    final name = layerElement.findElements('Name').first.text;
    final title = layerElement.findElements('Title').first.text;
    final workspace = name.contains(':') ? name.split(':')[0] : '';
    
    return Layer(
      name: name,
      title: title,
      url: baseUrl,
      workspace: workspace,
    );
  }

  String get wmsUrl => '$url?service=WMS&version=1.1.0&request=GetMap&layers=$name&format=image/png&transparent=true';
}