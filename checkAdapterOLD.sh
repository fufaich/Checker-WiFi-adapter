#!/bin/bash

sigHandler(){
    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null
    
    exit 0
}

createConfig(){
    echo > $confName 
    for key in "${!confList[@]}"; do
        echo "$key=${confList[$key]}" >> $confName
    done
}

setOption(){
    sed -i "s/\($2=\)\([^ ]*\)/\1$3/" $1
}

startAP(){
    sudo hostapd -B -P $pid $confName > $tmp

    if [[ $(grep -c "kernel reports" $tmp) -ne 0 ]]
    then 
        ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null
        sudo hostapd -B -P $pid $confName > $tmp
    fi
}

stopAP(){
    cat $$pid 2> /dev/null | sudo kill 2
}


test(){
for i in ${array5Mhz[@]}
do
    echo "Channel= $i"
done
}

getChannelsArrays(){
    numPhy=$(iw dev $nameInterface info | grep wiphy | awk '{print $2}')
    iw phy$numPhy info | sed -n '/Band 2:/q;p' | grep 'MHz \[' | cut -d ' ' -f4 | grep -o '[0-9]*' > num
    mapfile -t array2Mhz < num
    rm num

    iw phy$numPhy info | sed -n '/Band 2:/,/Band 4:/p' | grep 'MHz \[' | cut -d ' ' -f4 | grep -o '[0-9]*' > num
    mapfile -t array5Mhz < num
    rm num
    
}

testChannel(){
        setOption $confName "channel" $1
        startAP
        sleep 0.2
        res=$(grep "AP-ENABLED" $tmp)
        res=$?
        if [[ $res == 0 ]];
            then
                echo "Channel= $1 support"
                stopAP
                return 1
            else 
                echo "Channel= $1 not support"
                stopAP
                return 0
        fi
}

testChannels(){
    echo $(date) > $channelsLog
    echo $(date) > $resFile
    echo "2.4GHZ Channel test" >> $resFile
    for i in ${array2Mhz[@]}
    do
        testChannel $i >> $resFile
        if [[ $? == 1 ]]; then
            arraySupported2Mhz+=($i)
        fi
    done

    echo "5GHZ Channel test" >> $resFile
    setOption $confName ieee80211n 1
    setOption $confName hw_mode a
    for i in ${array5Mhz[@]}
    do
        testChannel $i >> $resFile
        if [[ $? == 1 ]]; then
            arraySupported5Mhz+=($i)

        fi

    done

    rm $channelsLog
    rm $tmp
}

configureHTConfigForWidthAndChannel(){
    option=$1
    channel=$2
    VHTCentr=0
    case "$option" in
     "[HT20]")
        HTmode="[HT20]"
        VHTmode=0
        ExpectedWidthMhz=20
        VHTCentr=0
    ;;
    "[HT40+]")
        HTmode="[HT40+]"
        VHTmode=0
        ExpectedWidthMhz=40
        VHTCentr=0
    ;;
    "[HT40-]")
        HTmode="[HT40-]"
        VHTmode=0
        ExpectedWidthMhz=40
        VHTCentr=0
    ;;
    "[VHT80+]")
        HTmode="[HT40+]"
        VHTmode=1
        ExpectedWidthMhz=80
        VHTCentr=$(( $channel + 6 ))
    ;;
    "[VHT80-]")
        HTmode="[HT40-]"
        VHTmode=1
        ExpectedWidthMhz=80
        VHTCentr=$(( $channel - 6 ))
    ;;
    "[VHT160+]")
        HTmode="[HT40+]"
        VHTmode=2
        ExpectedWidthMhz=160
        VHTCentr=$(( $channel + 14 ))
    ;;
     "[VHT160-]")
        HTmode="[HT40-]"
        VHTmode=2
        ExpectedWidthMhz=160
        VHTCentr=$(( $channel - 14 ))
    ;;
    esac
    setOption $confName "channel" $channel
    setOption $confName "ht_capab" $HTmode
    setOption $confName "vht_oper_chwidth" "$VHTmode"
    setOption $confName "vht_oper_centr_freq_seg0_idx" $VHTCentr
}

waitScan(){
    cnt=0
    while true;
    do
        res=$(sudo iw dev $nameInterface info | grep channel)
        res=$?
        if [[ $res == 0 ]] then
            return 1
        fi

        if [[ $cnt == 12 ]] then
            return 0
        fi
        sleep 1
        cnt=$(( $cnt+1 ))
    done
}

checkWidtAndChannel(){
    ExpectedWidthMhz=$1
    channel=$2
    sleep 1
    res=$(grep "AP-DISABLED" tmp.log)
    res=$?
    if [[ $res == 1 ]]; then
        waitScan
        if [[ $? == 0 ]]; then
            # echo 0
            return 0
        fi
        text=$(sudo iw dev $nameInterface info | grep "width:")
        width=$(awk '{print $6}' <<< $text)
        ch=$(awk '{print $2}' <<< $text)
        if [[ $width == $ExpectedWidthMhz ]]; then
            # echo 1
            return 1
        fi
    fi
    # echo 0
    return 0
}

testWidth(){
    for HTMODE in ${modesFor2MHz[@]}
    do
        echo "Test 2.4MHz on $HTMODE"
        setOption $confName hw_mode g
        for i in ${arraySupported2Mhz[@]}
        do
            configureHTConfigForWidthAndChannel $HTMODE $i
            startAP
            checkWidtAndChannel $ExpectedWidthMhz $i
            res=$?
            if [[ $res == 1 ]]; 
            then
                sed -i "/Channel= $i / s/$/ $HTMODE/" $resFile
            fi
            stopAP
        done
    done

    for HTMODE in ${modesFor5MHz[@]}
    do
        echo "Test 5MHz on $HTMODE"
        setOption $confName hw_mode a
        for i in ${arraySupported5Mhz[@]}
        do
 
            configureHTConfigForWidthAndChannel $HTMODE $i
            startAP
            checkWidtAndChannel $ExpectedWidthMhz $i
            res=$?
            if [[ $res == 1 ]]; 
            then
                echo "$HTMODE on $i"
                sed -i "/Channel= $i / s/$/ $HTMODE/" $resFile
            fi
            stopAP
        done
    done
}



########################################################
confName=hostapdTmp.conf
channelsLog=channels.log
pid=hostapd.pid
tmp=tmp.log
resFile=$2
nameInterface=$1
delay=0
declare -A confList
confList["interface"]=$nameInterface
confList["driver"]=nl80211
confList["country_code"]=RU
confList["ssid"]=WiFiOnLinux
confList["hw_mode"]=g
confList["channel"]=1
confList["ieee80211n"]=1
confList["ieee80211ac"]=1
confList["ht_capab"]="[HT20]"
confList["vht_oper_chwidth"]=0
confList["vht_oper_centr_freq_seg0_idx"]=0
modesFor2MHz=("[HT20]" "[HT40+]" "[HT40-]")
modesFor5MHz=("[HT20]" "[HT40+]" "[HT40-]" "[VHT80+]" "[HT80-]" "[VHT160+]" "[VHT160-]")
trap 'sigHandler' SIGINT

createConfig
getChannelsArrays
testChannels
testWidth

rm $confName
echo "Done"
