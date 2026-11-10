import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar

    // Dashboard state
    property int dashboardTab
    property string launcherQuery // set with launcher = true to open it pre-filled (drawers wallpapers)
    property date dashboardDate: new Date()
}
