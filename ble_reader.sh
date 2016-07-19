#!/bin/bash
# BLE services and characteristics reader

UUID_DESCRIPTIONS_FILE='./uuid_descriptions.txt'

MAC_ADDR=''

READ_VALUES=`echo $* | grep -- '--values'`
DECODE_UUIDS=`[ -r "$UUID_DESCRIPTIONS_FILE" ] && echo $* | grep -- '--uuids'`


print_help()
{
	echo "Usage: $0 MAC_ADDR [--values] [--uuids]"
	echo '  MAC_ADDR      MAC address of a device'
	echo '  --values      read values of all readable characteristics'
	echo '  --uuids       decode UUIDs of services and characteristics, according to Bluetooth SIG specification'
}

validate_mac_addr()
{
	FILTERED_MAC=`echo $1 | grep -Eo "^([0-9a-fA-F]{1,2}:){5}([0-9a-fA-F]{1,2})$"`
	[ -n "$FILTERED_MAC" ] && return 0 || return 1
}

validate_input()
{
	if validate_mac_addr $1 ; then
		MAC_ADDR=$1
	else
		echo 'Error: invalid MAC address provided.' > /dev/stderr
		print_help > /dev/stderr
		exit 1
	fi
}

# param: UUID to be decoded
get_uuid_description()
{
	UUID_DESCRIPTION=`cat $UUID_DESCRIPTIONS_FILE | sed s/'#.*$'// | grep "$1" | cut -d':' -f2`
	[ -n "$UUID_DESCRIPTION" ] && echo " (${UUID_DESCRIPTION})"
}

read_char_value()
{
	CHAR_VALUE=`gatttool -b $MAC_ADDR -t random --char-read -a $1 | sed s/'Characteristic value\/descriptor: '/''/`
	echo "$CHAR_VALUE (`echo $CHAR_VALUE | xxd -p -r`)"
}

decode_char_properties()
{
	(($1 & 0x01)) && OUT=$OUT'broadcast, '
	(($1 & 0x02)) && OUT=$OUT'read, '
	(($1 & 0x04)) && OUT=$OUT'write-without-response, '
	(($1 & 0x08)) && OUT=$OUT'write, '
	(($1 & 0x10)) && OUT=$OUT'notify, '
	(($1 & 0x20)) && OUT=$OUT'indicate, '
	(($1 & 0x40)) && OUT=$OUT'authenticated-write, '
	(($1 & 0x80)) && OUT=$OUT'extended-properties, '
	echo $OUT | sed s/',$'/''/
}

parse_service_line()
{
	SERV_HANDLE=$2
	SERV_UUID=$9
	SERV_UUID_DESCRIPTION=`[ -n "$DECODE_UUIDS" ] && get_uuid_description $SERV_UUID`
	echo "service: handle ${SERV_HANDLE}, UUID: ${SERV_UUID}${SERV_UUID_DESCRIPTION}"
}

parse_characteristic_line()
{
	CHAR_HANDLE=${2}
	CHAR_PROPS=${6}
	CHAR_VALUE_HANDLE=${11}
	CHAR_UUID=${14}
	CHAR_UUID_DESCRIPTION=`[ -n "$DECODE_UUIDS" ] && get_uuid_description $CHAR_UUID`
	echo " - char:         ${CHAR_UUID}${CHAR_UUID_DESCRIPTION}"
	echo " - properties:   $CHAR_PROPS (`decode_char_properties $CHAR_PROPS`)"
	echo " - char handle:  $CHAR_HANDLE"
	[ -n "$READ_VALUES" ] && ((CHAR_PROPS & 0x02)) && echo " - value:        `read_char_value $CHAR_VALUE_HANDLE`"
	echo " - value handle: $CHAR_VALUE_HANDLE"
}

parse_ble_output()
{
	while read line; do
		echo $line | grep -q '^service' && parse_service_line $line
		echo $line | grep -q '^char' && parse_characteristic_line $line
		echo
	done
}

get_services()
{
	gatttool -b $MAC_ADDR -t random --primary | sed s/'^attr handle = '/'service '/
}

get_characteristics()
{
	gatttool -b $MAC_ADDR -t random --characteristics | sed s/'^handle = '/'char '/
}

get_ble_data()
{
	get_services && get_characteristics
}

##########################################################

validate_input $*

get_ble_data | tr -d ',' | sort -k 2 | parse_ble_output



