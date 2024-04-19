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


    numPhy=$(iw dev $nameInterface info | grep wiphy | awk '{print $2}')
    iw phy$numPhy info | sed -n '/Band 4:/,${p;}' | grep 'MHz \[' | grep -v "(disabled)" | cut -d ' ' -f4 | grep -o '[0-9]*'> num
    mapfile -t array6GHz < num
    rm num
}

createConfig(){
    declare -A confList
    confList["interface"]=$nameInterface
    confList["hw_mode"]=$hw_mode
    confList["channel"]=$ch
    confList["driver"]=nl80211
    confList["ssid"]=WiFiOnLinux
    
    if [[ $mode6GHz == 1 ]]
    then
        confList["wpa_passphrase"]=myPW1234    
        confList["op_class"]=131
        confList["country_code"]=GB
        confList["ieee80211d"]=1
        confList["ieee80211n"]=1
        confList["auth_algs"]=3
        confList["wpa"]=2
        confList["wpa_pairwise"]=CCMP
        confList["wpa_key_mgmt"]=SAE
        confList["ieee80211w"]=2
        confList["wmm_enabled"]=1
        confList["ieee80211ac"]=1
        confList["ieee80211ax"]=1
        confList["ieee80211ax"]=1
    fi

    echo > $tmpConfig 
    for key in "${!confList[@]}"; do
        echo "$key=${confList[$key]}" >> $tmpConfig
    done

    unset confList
}
startStopAP(){
    sleep $delay
    
    sudo hostapd $tmpConfig > $tmp &
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
    # cat $tmp > $ch-$mode6GHz.log
    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null  
    rm $tmp
    rm $tmpConfig
}


testChannel(){
    if [[ $mode6GHz == 1 ]]
    then
            hw_mode="a"
    else
        if [[ $ch -gt 14 ]] 
        then
            hw_mode="a"

        else
            hw_mode="g"
        fi
    fi
    


    jsonObject+=" \"$ch\" :"
    createConfig
    startStopAP
}

mainLoop(){
    jsonObject+="\"2.4GHz/5GHz\" : {"
    for ch in "${array[@]}"
    do
        testChannel
    done
    jsonObject=${jsonObject%,} 
    jsonObject+="},"

    jsonObject+="\"6GHz\" : {"

    mode6GHz=1
    for ch in "${array6GHz[@]}"
    do
        testChannel
    done
    jsonObject=${jsonObject%,} 
    jsonObject+="}"
    
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
mode6GHz=0

jsonObject+="{"
getChannelsArrays
ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null   
echo "Testing..." 
mainLoop

jsonObject=${jsonObject%,} 
jsonObject+=" }"
echo $jsonObject > $resFile.json
echo "Done" 