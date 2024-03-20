#!/bin/bash
confName=hostapdTmp.conf
resFile=$2
nameInterface=$1
delay=0
numPhy=$(iw dev $nameInterface info | grep wiphy | awk '{print $2}')

sigHandler(){
    nul=$(ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null)
    exit 0
}

trap 'sigHandler' SIGINT


createConfig(){
    declare -A confList
    declare -A result
    confList["interface"]=$nameInterface
    confList["driver"]=nl80211
    confList["country_code"]=RU
    confList["ssid"]=WiFiOnLinux
    confList["hw_mode"]=g
    confList["channel"]=13
    confList["ieee80211n"]=0
    echo > $confName 
    for key in "${!confList[@]}"; do
        echo "$key=${confList[$key]}" >> $confName
    done
}
setOption(){
    sed -i "s/\($2=\)\([^ ]*\)/\1$3/" $1
}
testChannel(){
    channel=$1

    setOption $confName channel $i
    sudo hostapd -B -P hostapd.pid $confName > tmp.log
    sleep $delay
    if [[ $(grep -c "kernel reports" tmp.log) -ne 0 ]]
    then
        ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null
        sudo hostapd -B -P hostapd.pid $confName > tmp.log
    fi
    if [[ $(grep -c "frequency not allowed" tmp.log) -ne 0 || $(grep -c "not support configured channel" tmp.log) -ne 0 ]]
    then
        return 0
    else
        return 1
    fi
    
}

testChannels(){
    echo $(date) > channels.log
    echo $(date) > $resFile   

    iw phy$numPhy info | sed -n '/Band 4:/q;p' | grep 'MHz \[' | cut -d ' ' -f4 | grep -o '[0-9]*' > num
    mapfile -t array < num

    echo "2.4GHZ Channel test" >> $resFile
    json_object='{'
    for i in ${array[@]}
    do
        if [[ $i == 36 ]]
        then
            setOption $confName ieee80211n 1
            echo "ht_capab=[HT40+][SHORT-GI-20]" >> $confName
            echo "5GHZ Channel test" >> $resFile
            setOption $confName hw_mode a
        fi

        testChannel $i
        res=$?
        echo Channel: $i  = $(cat tmp.log) >> channels.log
        
        if [[ $res != 1 ]] then
            echo "Channel $i not supported">> $resFile
            json_object+="\"$i\":false,"
        else
            echo "Channel $i supported">> $resFile
            json_object+="\"$i\":true,"
        fi
    done
    json_object=${json_object%,} # Удаляем последнюю запятую
    json_object+='}'
    echo $json_object > $resFile.json

    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null
    rm tmp.log
    rm num
    rm $confName
    # rm channels.log
}

createConfig
testChannels

