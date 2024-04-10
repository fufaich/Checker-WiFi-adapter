#!/bin/bash

sigHandler(){
    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null   
    exit 0
}

getChannelsArrays(){
    numPhy=$(iw dev "$nameInterface" info | grep wiphy | awk '{print $2}')
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
    confList["country_code"]=RU
    case "$width" in
     "HT20")
        ExpectedWidthMhz=20
    ;;
    "HT40+")
        confList["ht_capab"]="[HT40+]"
        confList["ieee80211n"]=1
        ExpectedWidthMhz=40
    ;;
    "HT40-")
        confList["ht_capab"]="[HT40-]"
        confList["ieee80211n"]=1
        ExpectedWidthMhz=40
    ;;
    "HT80+")
        confList["ht_capab"]="[HT40+]"
        confList["vht_oper_chwidth"]=1
        confList["ieee80211n"]=1
        confList["ieee80211ac"]=1
        confList["vht_oper_centr_freq_seg0_idx"]=$center


        ExpectedWidthMhz=80
    ;;
     "HT80-")
        confList["ht_capab"]="[HT40-]"
        confList["vht_oper_chwidth"]=1
        confList["ieee80211n"]=1
        confList["ieee80211ac"]=1
        confList["vht_oper_centr_freq_seg0_idx"]=$center


        ExpectedWidthMhz=80
    ;;
    "HT160+")
        confList["ht_capab"]="[HT40+]"
        confList["vht_oper_chwidth"]=2
        confList["ieee80211n"]=1
        confList["ieee80211ac"]=1
        confList["vht_oper_centr_freq_seg0_idx"]=$center
        ExpectedWidthMhz=160
    ;;
    "HT160-")
        confList["ht_capab"]="[HT40-]"
        confList["vht_oper_chwidth"]=2
        confList["ieee80211n"]=1
        confList["ieee80211ac"]=1
        confList["vht_oper_centr_freq_seg0_idx"]=$center
        ExpectedWidthMhz=160
    ;;
    esac

    echo > $tmpConfig 
    for key in "${!confList[@]}"; do
        echo "$key=${confList[$key]}" >> $tmpConfig
    done

    unset confList
}
startStopAP(){
    sleep $delay
    sleep 0.2
    sudo hostapd $tmpConfig > $tmp &

##################################################### Ждём "полного" запуска
    while [[ true ]] 
    do          
        if [[ $(grep "AP-DISABLED" $tmp) || $(grep "AP-ENABLED" $tmp) ]]
        then
            break
        fi
        sleep 0.5
    done
################################################# Провека
    ch_width_center=$(sudo iw dev $nameInterface info | grep "channel")

    RealCh=$(echo $ch_width_center | awk -F'[ (]' '{print $2}')
    RealWidth=$(echo $ch_width_center | awk '{print $6}')
    RealCenter=$(echo $ch_width_center | grep -oP 'center1: \K\d+(?= MHz)')

    if [[ "$ch" == "$RealCh" && "$ExpectedWidthMhz" == "$RealWidth" ]]
    then
        echo "channel= $ch | $RealCh  width= $RealWidth | $ExpectedWidthMhz centr= $RealCenter true"
        res="$RealCenter"
    else
        echo "channel= $ch | $RealCh  width= $RealWidth | $ExpectedWidthMhz centr= $RealCenter false"
        res="0"
    fi

    # read key
########################################################
    # cat $tmp > "$ch-$width-$i-$center.log"

    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs sudo kill 2 2> /dev/null
    rm $tmp
    rm $tmpConfig
}


testChannel(){
    echo "Test $ch"
    if [[ $ch -gt 14 ]] 
    then
        hw_mode="a"
        ht_capab=("HT20" "HT40+" "HT40-" "HT80+" "HT80-" "HT160+" "HT160-")
        # ht_capab=("HT20" "HT40+" "HT40-")

    else
        hw_mode="g"
        ht_capab=("HT20" "HT40+" "HT40-")
        centers80=("42" "58" "106" "122" "138" "155" "171")
        centers160=("50" "114" "163")
    fi


    jsonObject+=" \"$ch\" : { "
    for width in "${ht_capab[@]}"
    do
        if [[ $width == "HT20" || $width == "HT40+" || $width == "HT40-" ]];
        then
            jsonObject+=" \"$width\" :  "
            createConfig
            startStopAP
            if [[ "$res" == "0" ]]
                then
                    jsonObject+="false,"
                else
                    jsonObject+="true,"
            fi
        elif [[ $width == "HT80+" || $width == "HT80-" ]]
        then
            jsonObject+=" \"$width\" :  "
            result=""
            flag=0
            for center in "${centers80[@]}" 
            do

                diff=$(( ($ch-$center) < 0 ? -($ch-$center) : ($ch-$center) ))
                if [ $diff -gt 15 ]
                then
                    echo "continue"
                    continue
                fi
                createConfig
                startStopAP
                if [[ "$res" != "0" ]]
                then
                    flag=1
                    result=$res
                fi
            done

            if [[ $flag == 1 ]]
                then
                    jsonObject+="\"$result\","
                else
                    jsonObject+="false,"
            fi
        else
            jsonObject+=" \"$width\" :  "
            result=""
            flag=0
            for center in "${centers160[@]}" 
            do
                
                diff=$(( ($ch-$center) < 0 ? -($ch-$center) : ($ch-$center) ))
                if [ $diff -gt 25 ]
                then
                    echo "continue"
                    continue
                fi


                createConfig
                startStopAP
                if [[ "$res" != "0" ]]
                then
                    flag=1
                    result=$res
                fi
            done

            if [[ $flag == 1 ]]
                then
                    jsonObject+="\"$result\","
                else
                    jsonObject+="false,"
            fi
        fi

    done
    jsonObject=${jsonObject%,} 
    jsonObject+=" },"
    echo "$jsonObject" > "$resFile.json"
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
tmp="tmp.log"
jsonObject=""
delay=0
trap 'sigHandler' SIGINT
jsonObject+="{"

getChannelsArrays
mainLoop

jsonObject=${jsonObject%,} 
jsonObject+=" }"
echo "$jsonObject" > "$resFile.json"
echo "Done" 