import QtQuick
import QtQuick.Controls as Controls

// The one story in this provider, as its own file. The adapter names it in
// the catalog; nothing in the harness knows this story exists, and adding a
// second one requires no change outside the catalog.
Rectangle {
    id: root

    property string variant: "default"

    implicitWidth: 320
    implicitHeight: 56
    radius: 12
    color: "#34415f"
    border.color: "#91c7ff"
    border.width: 2

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 20
        text: root.variant === "filled" ? "Filled from control" : "Generic text input"
    }
}
