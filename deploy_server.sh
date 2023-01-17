#!/bin/bash
###
# This is a simple script to deploy a community server on a Debian 11 VPS in minutes.
# Stats are synchronised with other community servers, and matches are automatically uploaded and announced in the community Discord.
# You will be prompted to accept the SteamCMD terms of service, after this no further interaction is needed.
# The server will automatically start and is ready to use without any further configuration.
# The required parameters below can be provided on request to anyone who wants to run an XMS server affiliated with the community:
SERVER_NAME="Australian Deathmatch"
REGIONCODE="5"
DEMOSYNC_KEYID="REDACTED"
DEMOSYNC_KEY="REDACTED"
DEMOSYNC_FOLDER="REDACTED"
DEMOSYNC_PREFIX="REDACTED"
WEBHOOK_M="REDACTED"
WEBHOOK_F="REDACTED"
STATS_PASSWORD="REDACTED"
###

URL_METAMOD="https://mms.alliedmods.net/mmsdrop/1.11/mmsource-1.11.0-git1148-linux.tar.gz" # https://www.sourcemm.net/downloads.php?branch=stable
URL_SOURCEMOD="https://sm.alliedmods.net/smdrop/1.11/sourcemod-1.11.0-git6926-linux.tar.gz" # https://www.sourcemod.net/downloads.php
URL_SSDK="https://github.com/Adrianilloo/SourceSDK2013/releases/download/Release-5/SourceSDK2013_Release-5.zip" # https://github.com/Adrianilloo/SourceSDK2013/releases
URL_VPHYSICS="https://builds.limetech.io/files/vphysics-1.0.0-hg93-linux.zip" # https://builds.limetech.io/?project=vphysics
URL_STEAMTOOLS="https://builds.limetech.io/files/steamtools-0.10.0-git179-54fdc51-linux.zip" # https://builds.limetech.io/?p=steamtools
URL_CLEANER="https://forums.alliedmods.net/attachment.php?attachmentid=111596&d=1351538952" # https://forums.alliedmods.net/showthread.php?p=1789738
URL_STEAMWORKS="http://users.alliedmods.net/~kyles/builds/SteamWorks/SteamWorks-git132-linux.tar.gz" # http://users.alliedmods.net/~kyles/builds/SteamWorks/
URL_GAMEME="https://github.com/gamemedev/plugin-sourcemod/releases/download/v.4.5.1/gameme_plugin_sourcemod_v4.5.zip" # https://github.com/gamemedev/plugin-sourcemod/releases
URL_SUPERLOGS="https://forums.alliedmods.net/attachment.php?attachmentid=68007&d=1276996567" # https://forums.alliedmods.net/showthread.php?t=126861
URL_RCBOT2="https://github.com/APGRoboCop/rcbot2/releases/download/1.5/rcbot2.zip" # https://github.com/APGRoboCop/rcbot2/releases

# Install required software
apt --assume-yes update
apt --assume-yes install software-properties-common
apt-add-repository non-free
dpkg --add-architecture i386
apt --assume-yes update
apt --assume-yes install lib32gcc-s1 lib32stdc++6 libtinfo5:i386 libncurses5:i386 libcurl3-gnutls:i386 screen wget zip unzip bzip2 vsftpd steamcmd dos2unix rclone

# Install HL2DM files under a new user
useradd -m -s /bin/bash srcds
cd /home/srcds/
ln -s /usr/games/steamcmd steamcmd
su srcds -c "./steamcmd +force_install_dir /home/srcds +login anonymous +app_update 232370 validate +quit"

mkdir -p .steam/sdk32
ln -s bin/steamclient.so .steam/sdk32/steamclient.so

# Install Adrianilloo's custom server binary
wget $URL_SSDK
unzip -j \*.zip "SourceSDK2013_Release-5/mod_hl2mp/bin/server.so" -d "/home/srcds/bin"
rm *.zip
cd /home/srcds/bin
ln -s soundemittersystem_srv.so soundemittersystem.so
ln -s scenefilecache_srv.so scenefilecache.so

# Install Metamod/Sourcemod/RCBot2 and extensions
cd /home/srcds/hl2mp
wget $URL_METAMOD
wget $URL_SOURCEMOD
wget $URL_VPHYSICS
wget $URL_STEAMTOOLS
wget $URL_STEAMWORKS
wget $URL_RCBOT2
wget https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/xms.zip
wget https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/xfov.zip
wget https://github.com/utharper/sourcemod-hl2dm/releases/download/latest/gameme_hud.zip

for file in `ls *.tar.gz`;
  do tar xzvf $file;
done
unzip -o \*.zip
rm *.zip
rm *.tar.gz

mkdir -p addons/plr
wget https://raw.githubusercontent.com/FoG-Plugins/Player-Limit-Remover/master/addons/plr.vdf -O addons/plr.vdf
wget https://github.com/FoG-Plugins/Player-Limit-Remover/raw/master/addons/plr/plr.so -O addons/plr/plr.so

cd addons/sourcemod
wget $URL_GAMEME
wget $URL_CLEANER -O cleaner.zip
wget $URL_SUPERLOGS -O plugins/superlogs-hl2mp.smx
wget $URL_UPDATER -O updater.zip
unzip -o \*.zip
rm *.zip

# Disable conflicting stock plugins
cd plugins
mv adminmenu.smx disabled/
mv funcommands.smx disabled/
mv funvotes.smx disabled/
mv basevotes.smx disabled/

# Fetch all maps from XMS maplists
cd /home/srcds/hl2mp/cfg
mv mapcycle_default.txt default.txt && cat mapcycle_*.txt >> ../maps/downloadlist.txt && mv default.txt mapcycle_default.txt
cd ../maps
dos2unix downloadlist.txt

while IFS="" read -r p || [ -n "$p" ]
do
  wget -nc https://fastdl.hl2dm.community/maps/$p.bsp.bz2
  bzip2 -d $p.bsp.bz2
done < downloadlist.txt
rm downloadlist.txt

# Server configuration
cd ..


sed -i "s|\"ServerName\"     \"Another XMS Server\"|\"ServerName\"     \"$SERVER_NAME\"|" addons/sourcemod/configs/xms.cfg
sed -i "s|\"DemoExtension\"  \".dem\"|\"DemoExtension\"  \".zip\"|" addons/sourcemod/configs/xms.cfg
sed -i "s|\"DemoURL\"        \"\"|\"DemoURL\"        \"https://hl2dm.community/demos/$DEMOSYNC_FOLDER\"|" addons/sourcemod/configs/xms.cfg
sed -i "s|\"MatchWebhook1\"     \"\"|\"MatchWebhook1\"     \"$WEBHOOK_M\"|" addons/sourcemod/configs/xms.cfg
sed -i "s|\"FeedbackWebhook\"   \"\"|\"FeedbackWebhook\"   \"$WEBHOOK_F\"|" addons/sourcemod/configs/xms.cfg
sed -i "s|\"FooterText\"|//\"FooterText\"|" addons/sourcemod/configs/xms.cfg

sed -i "s|hostname \"Another XMS Server\"|hostname \"[λ] $SERVER_NAME — hl2dm.community\"|" cfg/server.cfg
sed -i "s|sv_region \"5\"|sv_region \"$REGIONCODE\"|" cfg/server.cfg
sed -i "s|rcon_password \"\"|rcon_password \"$STATS_PASSWORD\"|" cfg/server.cfg
echo -e "\n\nlogaddress_delall\nlogaddress_add logs.hl2dm.community:31434" >> cfg/server.cfg

sed -i "s|rcbot_show_welcome_msg 1|rcbot_show_welcome_msg 0|" addons/rcbot2/config/config.ini
sed -i "s|rcbot_bot_quota_interval -1|rcbot_bot_quota_interval 0|" addons/rcbot2/config/config.ini
sed -i "s|rcbotd config min_bots -1|rcbotd config min_bots 0|" addons/rcbot2/config/config.ini
sed -i "s|rcbotd config max_bots 10|rcbotd config max_bots 0|" addons/rcbot2/config/config.ini
sed -i "s|sm plugins unload|#sm plugins unload|g" addons/rcbot2/config/config.ini
sed -i "s|sv_quota_stringcmdspersecond|#sv_quota_stringcmdspersecond|" addons/rcbot2/config/config.ini
sed -i "s|rcbot_loglevel 2|rcbot_loglevel 0|" addons/rcbot2/config/config.ini
echo "\nrcbot_tooltips 0" >> addons/rcbot2/config/config.ini
rm addons/rcbot2/profiles/*.ini
cat >addons/rcbot2/profiles/1.ini <<EOF
name = Percy
visionticks_clients = 2
visionticks = 100
pathticks = 100
braveness = 70
aim_skill = 60
sensitivity = 5
EOF

cat >addons/sourcemod/configs/cleaner.cfg <<EOF
playerinfo
gameme_raw_message
[RCBot]
[RCBOT2]
rcon
Ignoring unreasonable position
"Server" requested "top10"
DataTable
Interpenetrating entities
logaddress_
gameME
changed cvar
ConVarRef room_type
Writing cfg/banned_
RecordSteamInterfaceCreation
Could not find steamerrorreporter binary
Bogus constraint
EOF

cd ..

cat >autoupdate <<EOF
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
force_install_dir /home/srcds
login anonymous
app_update 232370
quit
EOF

cat >START_SERVER <<EOF
#!/bin/bash
rm -rf hl2mp/logs/*
rm -rf hl2mp/addons/sourcemod/logs/L*.log

screen -S hl2dm -d -m ./srcds_run -console -game hl2mp +map dm_lockdown +maxplayers 20 -tickrate 100 -autoupdate -steam_dir /home/srcds/ -steamcmd_script /home/srcds/autoupdate +port 27015 +tv_port 27020 +clientport 27005

exit 0
EOF
chmod +x START_SERVER

# Setup demo syncing
mkdir -p /home/srcds/hl2mp/demos/incomplete
su srcds -c "rclone config create demosync b2 account $DEMOSYNC_KEYID key $DEMOSYNC_KEY hard_delete false"

cat >hl2mp/demos/SYNC <<\EOF
#!/bin/bash
cd /home/srcds/hl2mp/demos

for file in *.dem; do
  zip "${file%.*}.zip" "$file" "$file.txt"
  rclone copy "${file%.*}.zip" demosync:DEMOSYNC_PREFIX/DEMOSYNC_FOLDER/
  rm "$file" "$file.txt"
done

exit 0
EOF
sed -i "s|DEMOSYNC_PREFIX|$DEMOSYNC_PREFIX|" hl2mp/demos/SYNC
sed -i "s|DEMOSYNC_FOLDER|$DEMOSYNC_FOLDER|" hl2mp/demos/SYNC

# Cronjobs
cat >CRON <<EOF
@reboot sleep 10;/bin/bash /home/srcds/START_SERVER
* * * * * /bin/bash /home/srcds/hl2mp/demos/SYNC
EOF
su srcds -c "crontab CRON"
rm CRON

# Enable FTP writing
sed -i "s/#write_enable=YES/write_enable=YES/" /etc/vsftpd.conf
systemctl restart vsftpd

# Finalise
chown -R srcds /home/srcds/
su srcds -c "./START_SERVER"

echo -e "\n\n[DONE] Server setup has completed and it should now be running:"
echo "-- Use command \"screen -r\" to access the server console."
echo "-- To minimise the server console, hold CTRL and press A + D."
echo "-- To stop the server, press CTRL + C while inside the console."
echo "-- To start the server, reboot or use command: \"./START_SERVER\" from the home directory (cd ~)."
echo "-- You can SSH/FTP into the server using the username srcds and the password you set below:"
passwd srcds
ls
su srcds
exit 0