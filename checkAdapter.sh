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
    confList["country_code"]=RU
    confList["ssid"]=WiFiOnLinux

    echo > $tmpConfig 
    for key in "${!confList[@]}"; do
        echo "$key=${confList[$key]}" >> $tmpConfig
    done

    cat $tmpConfig >> "configs.log"

    unset confList
}
startStopAP(){
    sleep 0.2
    echo "StartAP" >> "configs.log"
    echo >> "configs.log"
    hostapd -B -P $pid $tmpConfig > $tmp

    res=$(grep "AP-DISABLED" $tmp)
    cat $tmp > $ch.log
    if [[ $res ]]; then
            jsonObject+=" false ,"
        else
            jsonObject+=" true ,"
    fi

    cat $pid 2> /dev/null | xargs kill 2

}


testChannel(){
    if [[ $ch -gt 14 ]] ; then
        hw_mode="a"
    else
        hw_mode="g"
    fi

    jsonObject+=" \"$ch\" :"
    createConfig
    startStopAP

    widthsResult+=(})
}

mainLoop(){
    for ch in ${array[@]} 
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
declare -A ChannelsRes

jsonObject+="{"
echo > "configs.log"
getChannelsArrays
mainLoop

jsonObject=${jsonObject%,} 
jsonObject+=" }"
echo $jsonObject > $resFile.json