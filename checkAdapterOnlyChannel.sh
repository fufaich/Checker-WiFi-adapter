#!/bin/bash

sigHandler(){
    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs kill 2 2> /dev/null   
    exit 0
}

getChannelsArrays(){
    iw phy$numPhy info | sed -n '/Band 4:/q;p' | grep 'MHz \[' | grep -v "(disabled)" | cut -d ' ' -f4 | grep -o '[0-9]*' > num
    mapfile -t array < num
    rm num

    if [ $check6GHz ]
    then
        iw phy$numPhy info | sed -n '/Band 4:/,${p;}' | grep 'MHz \[' | grep -v "(disabled)" | cut -d ' ' -f4 | grep -o '[0-9]*'> num
        mapfile -t array6GHz < num
        rm num
    fi
    
}

createConfig(){
    echo > $tmpConfig 
    echo "interface=$nameInterface" >> $tmpConfig
    echo "hw_mode=$hw_mode" >> $tmpConfig
    echo "channel=$ch" >> $tmpConfig
    echo "driver=nl80211" >> $tmpConfig
    echo "ssid=WiFiOnLinux" >> $tmpConfig
    echo "noscan=1" >> $tmpConfig
    
    if [[ $mode6GHz == 1 ]]
    then
        echo "wpa_passphrase=myPW1234" >> $tmpConfig  
        echo "op_class=131" >> $tmpConfig
        echo "country_code=$countryCode" >> $tmpConfig
        echo "ieee80211d=1" >> $tmpConfig
        echo "ieee80211n=1" >> $tmpConfig
        echo "auth_algs=3" >> $tmpConfig
        echo "wpa=2" >> $tmpConfig
        echo "wpa_pairwise=CCMP" >> $tmpConfig
        echo "wpa_key_mgmt=SAE" >> $tmpConfig
        echo "ieee80211w=2" >> $tmpConfig
        echo "wmm_enabled=1" >> $tmpConfig
        echo "ieee80211ac=1" >> $tmpConfig
        echo "ieee80211ax=1" >> $tmpConfig
        echo "ieee80211ax=1" >> $tmpConfig
    fi

}
startAP(){
    hostapd $tmpConfig > $tmp &
    while [[ true ]] 
    do          
        if [[ $(grep "AP-DISABLED" $tmp) || $(grep "AP-ENABLED" $tmp) ]]
        then
            break
        fi
        sleep 0.5
    done
}

stopAP(){




    ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs kill 2 2> /dev/null  
    rm $tmp
    rm $tmpConfig
}

test20MHz(){
    echo "test20MHz"
    createConfig
    startAP
    

    res=$(grep "AP-ENABLED" $tmp)
    if [[ $res ]] 
        then
            echo "20MHz[$ch] true"
        else
            echo "20MHz[$ch] false"
    fi

    cat $tmp > $ch-$mode6GHz.log
    stopAP 
}

test40MHz(){
    echo "test40MHz"
}

test80MHz(){
    centers80=("42" "58" "106" "122" "138" "155" "171")
    echo "test80MHz"
}

test160MHz(){
    centers160=("50" "114" "163")
    echo "test160MHz"
}



testChannel(){
    sleep $delay
    echo "Ch=$ch"

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

    test20MHz
    # test40MHz
    # test80MHz
    # test160MHz
}

jsonWritter(){

    

    case $1 in
        "start")
            declare -A array24
            declare -A array5
            declare -A array6
            json_object="{ "
        ;;

        "addCh")
            json_object+="\"$ch\": "
        ;;

        "end")
            echo "}" >> "$resFile"
        
        ;;

        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
        ;;
    esac
}

mainLoop(){
    for ch in "${array[@]}"
    do
        testChannel
    done

    if [ $check6GHz ]
    then
        mode6GHz=1
        for ch in "${array6GHz[@]}"
        do
            testChannel
        done
    fi
}

checkRoot(){
    if [ "$EUID" -ne 0 ]
    then
        echo "Please run this script as root or use sudo."
        exit 1
    fi
}

checkParams(){
    # Флаги по умолчанию
    check6GHz=false

    # Цикл обработки флагов
    while getopts ":6h" opt
    do
        case $opt in
            6)
            check6GHz=true
            ;;

            h)
            echo "Command [-6h] <interface> <file>"
            echo "-6 add check on 6GHz"
            echo "-h show this usage"
            exit 0
            ;;

            \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        esac
    done
    shift $((OPTIND-1))

    if [ "$#" -ne 2 ]
    then
        echo "Required 2 arguments."
        echo "Command <interface> <filename>"
        exit 1
    fi

}

checkInterface(){
    iw dev "$1" info 2> /dev/null > /dev/null
    
    if [ $? -ne 0 ]
    then
        echo "checkInterface error"
        echo "Please check interface name"

        exit 1
    fi
    numPhy=$(iw dev $1 info 2> /dev/null | grep wiphy | awk '{print $2}')

    str=$(rfkill | grep "phy$numPhy")
    if [ $? -ne 0 ]
    then
        echo "checkInterface error"
        echo "Please check interface name"

        exit 1
    fi

    rfId=$(echo "$str" | awk '{print $1}')
    if [[ $(echo "$str" | awk '{print $4}') != "unblocked" ]]
    then
        echo "Unblock interface"
        rfkill unblock "$rfId"
    fi

    if [[ $(echo "$str" | awk '{print $5}') != "unblocked" ]]
    then
        echo "Interface hard blocked"
        exit 1
    fi
}

############################################################
checkRoot
checkParams "$@"
shift $((OPTIND-1))
trap 'sigHandler' SIGINT
nameInterface=$1
resFile=$2
delay=0.2
checkInterface $nameInterface


tmpConfig=hostapdTmp.conf
tmp="tmp.log"
mode6GHz=0
countryCode=$(iw reg get | grep "country" | awk '{print $2}' | tr -d ':')

getChannelsArrays
ps aux | grep hostapd | awk '{if($1  == "root"){ print $2}}' | xargs kill 2 2> /dev/null   
echo "Testing..." 
mainLoop
# jsonWritter "start"
# jsonWritter "end"


# jsonObject=${jsonObject%,} Удаляет последнюю запятую
echo "Done" 