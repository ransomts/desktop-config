// What crosses the wallpaper now and then (PetSecrets.qml decides when; spoilers there):
// a shooting star, or a small flying saucer. Drawn from PetSecrets.skyT, which moves twenty
// times a second while one is up; nothing here has a timer, and nothing is drawn otherwise.
import QtQuick

Item {
    id: skyItem
    readonly property string what: PetSecrets.sky
    readonly property real t: PetSecrets.skyT
    readonly property bool ltr: PetSecrets.skyLtr
    visible: what !== ""

    Item {      // the star: a short bright streak sliding down across a third of the screen
        visible: skyItem.what === "star"
        readonly property real along: skyItem.width * (0.2 + 0.36 * skyItem.t)
        x: skyItem.ltr ? skyItem.width * 0.1 + along : skyItem.width * 0.9 - along
        y: skyItem.height * (PetSecrets.skyY + 0.14 * skyItem.t)
        opacity: Math.sin(Math.PI * skyItem.t)
        rotation: skyItem.ltr ? 21 : 159
        Rectangle {
            x: -110; y: -1; width: 110; height: 2; radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#00ffffff" }
                GradientStop { position: 1; color: "#f0ffffff" }
            }
        }
        Rectangle { x: -3; y: -3; width: 6; height: 6; radius: 3; color: "#ffffff" }
    }

    Item {      // the saucer: slowly across, bobbing, its lights running round
        visible: skyItem.what === "ufo"
        readonly property real across: (skyItem.width + 120) * skyItem.t - 60
        x: skyItem.ltr ? across : skyItem.width - across
        y: skyItem.height * PetSecrets.skyY + Math.sin(skyItem.t * 28) * 9
        rotation: Math.sin(skyItem.t * 28 + 1) * 5
        Rectangle { x: -11; y: -13; width: 22; height: 18; radius: 9; color: "#a07fd6c2"; border.width: 1; border.color: "#c8e8e0" }
        Rectangle { x: -28; y: -4; width: 56; height: 13; radius: 6; color: "#9aa0a6"; border.width: 1; border.color: "#4a4e55" }
        Repeater {
            model: 4
            Rectangle {
                required property int index
                x: -21 + index * 12; y: 1; width: 5; height: 4; radius: 2
                color: Math.floor(skyItem.t * 70) % 4 === index ? "#f56600" : "#5a5e66"
            }
        }
    }
}
