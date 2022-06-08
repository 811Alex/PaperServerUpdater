# PaperServerUpdater
Simple bash script that shows changelogs from the currently installed version of Paper, to the latest version available, then automatically installs the latest version and checks the integrity of the downloaded build.
It also shows the changelogs from upstream (e.g. Spigot).

You can also specify which Minecraft version or Paper build you want. Technically this means you can even downgrade, but be careful, downgrading the Minecraft version can corrupt your world and neither me nor the Paper staff will provide support in that case.

The script was designed to be usable in other scripts. It also makes a symlink to the latest build, that has a static name, so you can use that in scripts too.

Keep in mind that the Paper's devs have, in the past, changed how certain things work, which means that for very old builds, changelogs might not appear correctly. This script focuses on how the APIs it uses (currently Paper API V2) and the build comments function on the latest builds.

__Requires__: jq, curl, wget, awk, sed, coreutils, util-linux

## Sample ##
![Image showing the script at work](https://raw.githubusercontent.com/811Alex/PaperServerUpdater/master/sample.png)
