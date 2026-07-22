{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // A relative URL works for both GitHub Pages and Electron's file:// shell.
    // The generated default uses /canvaskit for local CanvasKit, which points
    // at the drive root and leaves the packaged desktop window black.
    canvasKitBaseUrl: 'canvaskit/',
  },
});
