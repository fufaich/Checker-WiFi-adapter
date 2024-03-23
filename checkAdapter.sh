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
    confList["interface"]=$nameInterface
    confList["driver"]=nl80211
    confList["country_code"]=RU
    confList["ssid"]=WiFiOnLinux
    confList["hw_mode"]=g
    confList["channel"]=13
    confList["ieee80211n"]=1
    confList["ieee80211ac"]=1
    confList["ht_capab"]="[HT20]"
    confList["vht_oper_chwidth"]=0
    confList["vht_oper_centr_freq_seg0_idx"]=0

    echo > $confName 
    for key in "${!confList[@]}"; do
        echo "$key=${confList[$key]}" >> $confName
    done
}
setOption(){
    sed -i "s/\($2=\)\([^ ]*\)/\1$3/" $1
}

startAP(){
    sudo hostapd -B -P hostapd.pid $confName > tmp.log

    if [[ $(grep -c "kernel reports" tmp.log) -ne 0 ]]
    then 
        ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null
        sudo hostapd -B -P hostapd.pid $confName > tmp.log
    fi

}

stopAP(){
    cat hosapd.pid 2> /dev/null | sudo kill 2
}

waitScan(){
    cnt=0
    while true;
    do
        res=$(sudo iw dev $nameInterface info | grep channel)
        # sudo iw dev $nameInterface info | grep channel
        
        res=$?
        if [[ $res == 0 || $cnt == 5 ]] then
            return
        fi
        sleep 1
        cnt=$(( $cnt+1 ))
        # echo $cnt
    done
}

testChannel(){
    res=0
    channel=$1

    setOption $confName channel $channel
    setOption $confName "ht_capab" " "
    setOption $confName "vht_oper_chwidth" 0
    setOption $confName "ieee80211ac" 0
    setOption $confName "vht_oper_centr_freq_seg0_idx" 0


    startAP 
    sleep 0.2
    res=$(grep "AP-ENABLED" tmp.log)
    res=$?
    cat hostapd.pid 2> /dev/null | sudo kill 2
    return $res
}

testHT(){
    option=$1
    case "$option" in
    "[HT40+]")
        HTmode="[HT40+]"
        VHTmode=0
        mhz=40
    ;;
    "[HT40-]")
        HTmode="[HT40-]"
        VHTmode=0
        mhz=40
    ;;
    "[VHT80+]")
        HTmode="[HT40+]"
        VHTmode=1
        mhz=80
        setOption $confName "vht_oper_centr_freq_seg0_idx" $(( $channel + 6))
    ;;
    "[VHT80-]")
        HTmode="[HT40-]"
        VHTmode=1
        mhz=80
        setOption $confName "vht_oper_centr_freq_seg0_idx" $(( $channel + 6))
    ;;
    "[VHT160-]")
        HTmode="[HT40-]"
        VHTmode=1
        mhz=160
        setOption $confName "vht_oper_centr_freq_seg0_idx" $(( $channel - 14))
    ;;
     "[VHT160+]")
        HTmode="[HT40+]"
        VHTmode=2
        mhz=160
        setOption $confName "vht_oper_centr_freq_seg0_idx" $(( $channel + 14))
    ;;

    esac

    stopAP
    setOption $confName "channel" $channel
    setOption $confName "ht_capab" $HTmode
    setOption $confName "vht_oper_chwidth" $VHTmode
    setOption $confName "ieee80211ac" 1
    startAP
    sleep 1
    res=$(grep -q "AP-DISABLED" tmp.log)
    res=$?
    
    if [[ $res == 1 ]] then
        waitScan
        text=$(sudo iw dev $nameInterface info | grep "width:")
        width=$(awk '{print $6}' <<< $text)
        ch=$(awk '{print $2}' <<< $text)
        # echo "Width $width == mhz = $mhz"
        if [[ $width == "$mhz" ]] then
            echo "add [$width==$mhz]"
            echo "add [$option ch=$ch]"
            echo -n "[$option ch=$ch]"  >> $resFile
            stopAP
            return 1
        fi
    fi
    stopAP
    return 0
}
testWidth(){
    channel=$2
    resFile=$1
    echo -n "   Supported width: [HT20]" >> $resFile

    testHT "[HT40+]" $channel
    r1=$? 
    testHT "[HT40-]" $channel
    r2=$? 
    if [[ $r1 == 0 && $r2 == 0 ]] then
        echo >> $resFile
        return 0
    fi
    testHT "[VHT80+]" $channel
    testHT "[VHT80-]" $channel

    # testHT "[VHT80-]" $channel
    # testHT "[VHT80+-2]" $channel
    # testHT "[VHT80--2]" $channel
    # testHT "[VHT80++2]" $channel
    # testHT "[VHT80-+0]" $channel

    testHT "[VHT160+]" $channel
    testHT "[VHT160-]" $channel

    echo >> $resFile
}

testChannels(){
    echo $(date) > channels.log
    echo $(date) > $resFile   
    declare -A result
    iw phy$numPhy info | sed -n '/Band 4:/q;p' | grep 'MHz \[' | cut -d ' ' -f4 | grep -o '[0-9]*' > num
    mapfile -t array < num

    echo "2.4GHZ Channel test" >> $resFile
    json_object='{'
    for i in ${array[@]}
    do
        echo "Channel= $i"
        if [[ $i == 36 ]]
        then
            echo "5GHZ Channel test" >> $resFile
            setOption $confName ieee80211n 1
            setOption $confName hw_mode a
        fi
        sleep $delay
        testChannel $i
        res=$?
        echo Channel: $i  = $(cat tmp.log) >> channels.log
        if [[ $res == 1 ]] then
            echo "Channel $i not supported">> $resFile
            json_object+="\"$i\":false,"
        else
            echo  -n "Channel $i supported">> $resFile
            testWidth $resFile $i
            json_object+="\"$i\":true,"
        fi
        
        stopAP
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

echo "Done"