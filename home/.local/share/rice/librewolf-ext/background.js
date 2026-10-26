// The host script sends a theme object whenever the wallpaper colours change.
function connect() {
  const port = browser.runtime.connectNative("rice_theme");
  port.onMessage.addListener(theme => browser.theme.update(theme));
  port.onDisconnect.addListener(() => setTimeout(connect, 5000));
}
connect();
