#!/bin/bash

sigHandler(){
    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null   
    exit 0
}

getChannelsArrays(){
    numPhy=$(iw dev $nameInterface info | grep wiphy | awk '{print $2}')
    iw phy$numPhy info | sed -n '/Band 4:/q;p' | grep 'MHz \[' | grep -v "(disabled)" | cut -d ' ' -f4 | grep -o '[0-9]*' > num
    mapfile -t array < num
    rm num

}

createConfig(){
    declare -A confList
    confList["interface"]=$nameInterface
    confList["hw_mode"]=$hw_mode
    confList["channel"]=$ch
    confList["driver"]=nl80211
    confList["ssid"]=WiFiOnLinux

    echo > $tmpConfig 
    for key in "${!confList[@]}"; do
        echo "$key=${confList[$key]}" >> $tmpConfig
    done

    unset confList
}
startStopAP(){
    sleep $delay
    hostapd -B -P $pid $tmpConfig > $tmp


     while [[ true ]] 
    do          
        if [[ $(grep "AP-DISABLED" $tmp) || $(grep "AP-ENABLED" $tmp) ]]
        then
            break
        fi
        sleep 0.5
    done


    res=$(grep "AP-ENABLED" $tmp)
    if [[ $res ]] 
        then
            jsonObject+=" true ,"
        else
            jsonObject+=" false ,"
    fi
    # cat $tmp > $ch.log
    cat $pid 2> /dev/null | xargs kill 2
    rm $tmp
    rm $tmpConfig
}


testChannel(){
    if [[ $ch -gt 14 ]] 
    then
        hw_mode="a"

    else
        hw_mode="g"
    fi


    jsonObject+=" \"$ch\" :"
    createConfig
    startStopAP
}

mainLoop(){
    for ch in "${array[@]}"
    do
        testChannel
    done
}





############################################################
nameInterface=$1
resFile=$2
tmpConfig=hostapdTmp.conf
pid=hostapd.pid
tmp="tmp.log"
jsonObject=""
delay=0.2
trap 'sigHandler' SIGINT

jsonObject+="{"
getChannelsArrays
mainLoop

jsonObject=${jsonObject%,} 
jsonObject+=" }"
echo $jsonObject > $resFile.json
echo "Done" 