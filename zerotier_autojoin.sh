<<<<<<< HEAD
#!/bin/bash
### Created by Jatinder Grewal @ j@grewal.co 
# This script will automatically join a new member (device) to a ZeroTier network. Can be used with cloud-init or during other deployment tools.
# At minimum, the Network ID must be specified to join the specified network. If an API Key is also specified, this will be used to authorize the member (i.e., getting true access and assigned a ZT IP).
# If the device is already a member but not authorized, running the script specifying an API Key will just authorize the member.

# For usage and prerequisites, see below or run the script with the --help option.
# CAUTION: curl, jq, and zerotier-one need to be installed for the script to work correctly.

function usage {
  cat <<EOFUSAGE
  This script will automatically join a new device (member) to a ZeroTier network. Can be used with cloud-init or during other deployment tools.

  USAGE: $0 --network=<32charalphanum> --api=<32charalphanum> [ <other options: see below> ]

  OPTIONS:
    -a=,  --api=
            (32 digit alphanumeric key) OPTIONAL. Specifies the ZeroTier API Token (account) to authorize the device - i.e., getting true access and assigned a ZT IP.
            NOTE: If not specified, the device will still be joined to the network but not able to communicate with other devices until authorized by an admin or by running this script with the --api option.

    -u=,  --url=
            (HTTPS) OPTIONAL. URL to a standalone ZeroTier network controller API (Moon).
            Default value is https://my.zerotier.com/api as this is the public network controller default configured in every ZeroTier client.
            NOTE: This argument is only for those who run a standalone ZeroTier network controller.

    -n=, --network=
            (16 digit alphanumeric key) REQUIRED. The ZeroTier network (Network ID) to join.
            NOTE: A Network ID must be specified.

    -m=,  --member=
            (STRING) OPTIONAL. RECOMMENDED. Configures the device member shortname used by this client for the specific ZeroTier network.
            Default action is to use the unique device Node ID (10-digit alphanumeric) as member shortname. Use this option to set a more recognizable value.
            NOTE: Name must only be enclosed in quotes (" ") if any spaces are used. Though spaces will be replaced with dashes (-) for DNS compatibility.
            This setting is an object value stored inside each ZeroTier network. As a client, it is therefore possible to use a different short name inside each network.
            Joining via the zerotier-cli utility will not configure any shortname and leave an empty value. This can cause problems if pulling data for DNS use.

    -d=,  --description=
            (STRING) OPTIONAL. RECOMMENDED. Configures the device member description field for this client.
            NOTE: Description must only be enclosed in quotes (" ") if any spaces are used.
            This setting is an object value stored inside each ZeroTier network. As a client, it is therefore possible to use a different description field inside each network.
            Joining via the zerotier-cli utility will not configure any description and leave an empty value.

  PREREQUISITES:
    APPLICATIONS: zerotier-one, curl, jq
EOFUSAGE
}

# Builtin default values. Do not change these.
APIKEY=
NETWORKID=all
APIURL="https://my.zerotier.com/api"
SILENT=false
VERBOSE=false
MYID=$(zerotier-cli info | cut -d " " -f 3)
HOSTNAME=$MYID
DESCRIPTION=

args=()
while (( $# > 0 )); do
    arg="$1"
    arg_key="${arg%%=*}"
    arg_data="${arg#*=}"
    case $arg_key in
        --help|-h)          usage; exit 0               ;;
        --api|-a)           APIKEY=${arg_data}          ;;
        --url|-u)           APIURL=${arg_data}          ;;
        --network|-n)       NETWORKID=${arg_data}       ;;
        --member|-m)        HOSTNAME=${arg_data}        ;;
        --description|-d)   DESCRIPTION=${arg_data}     ;;
    esac
    shift
done

# Uncomment and change any of these variables below to override args
# APIKEY="32xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# NETWORKID="16xxxxxxxxxxxxxx"
# SILENT=false
# VERBOSE=false
# HOSTNAME=$MYID
# DESCRIPTION=`hostname -s`
# Uncomment and change any of these variables above to override args

# Normalize runtime arguments
SILENT=$(echo "$SILENT" | awk '{print tolower($0)}')
VERBOSE=$(echo "$VERBOSE" | awk '{print tolower($0)}')
HOSTNAME=$(echo "$HOSTNAME" | sed 's/ /-/g' | awk '{print tolower($0)}')

# Check if arguments are set or dependencies are installed
[[ ! -x "$(command -v jq)" ]] && { echo "Error: jq JSON processor is not installed or in PATH. See https://stedolan.github.io/jq/download/"; exit 1; }
[[ ! -x "$(command -v curl)" ]] && { echo "Error: curl command-line tool is not installed or in PATH"; exit 1; }
[[ -z "$APIKEY" ]] && { echo "Error: API Token must be specified."; usage; exit 1; }
[[ "$NETWORKID" == all ]] && { echo "Error: NETWORK ID not specified."; usage; exit 1; }
[[ ! $(echo "$APIKEY" | awk '{print length}') == 32 ]] && { echo "Syntax Error: API Token can only be a 32-digit alphanumeric value"; exit 1; }
[[ ! "$NETWORKID" == all && ! $(echo "$NETWORKID" | awk '{print length}') == 16 ]] && { echo "Syntax Error: Network ID can only be a 16-digit alphanumeric value"; exit 1; }
# End argument check

function zt_member_auth {
    JSON=$(curl -s -H "Authorization: Bearer $APIKEY" "$APIURL/network/$NETWORKID/member/$MYID" | jq -c --arg name "$HOSTNAME" --arg description "$DESCRIPTION" '.config.authorized=true | .name=$name | .description=$description')
    curl -s -o /dev/null -H "Authorization: Bearer $APIKEY" -d "$JSON" "$APIURL/network/$NETWORKID/member/$MYID"
    # New member - wait for local client to get updated
    echo -ne "waiting for network auth to register"
    while [ -z "$(zerotier-cli listnetworks | grep "$NETWORKID" | grep OK)" ]; do echo -ne "."; sleep 1; done
    echo -ne '\n'
}

# Join or already a member?
if [ -z "$(zerotier-cli listnetworks | grep "$NETWORKID")" ]; then
    echo "Not a member... Joining $NETWORKID"
    zerotier-cli join "$NETWORKID"
    echo -ne "Waiting for connection to $NETWORKID"
    while [ -z "$(zerotier-cli listnetworks | grep "$NETWORKID" | grep ACCESS_DENIED)" ]; do echo -ne "."; sleep 1; done
    echo -ne '\n'
    echo "Joined network, but need authentication"
    if [ -n "$APIKEY" ]; then
        echo "API Token will be used to authorize $MYID"
        zt_member_auth
        MYIP=$(zerotier-cli get "$NETWORKID" ip)
        echo "Device connected to $NETWORKID with IP $MYIP"
    fi # Auth new member
else
    if [ -n "$APIKEY" ]; then
        echo "Device already a member of $NETWORKID"
        echo "API Key will be used to authorize $MYID"
        zt_member_auth
        MYIP=$(zerotier-cli get "$NETWORKID" ip)
        echo "Device connected to $NETWORKID with IP $MYIP"
        exit 0
    fi # Auth existing member
    MYIP=$(zerotier-cli get "$NETWORKID" ip)
    [[ -z "$MYIP" ]] && { echo "Already a member of $NETWORKID but not authorized"; exit; }
    echo "Device already a member with IP $MYIP"
fi # Join member

exit 0
=======
{\rtf1\ansi\ansicpg1252\cocoartf2709
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\pard\tx720\tx1440\tx2160\tx2880\tx3600\tx4320\tx5040\tx5760\tx6480\tx7200\tx7920\tx8640\pardirnatural\partightenfactor0

\f0\fs24 \cf0 #!/bin/bash\
# This script will automatically join a new member (device) to a ZeroTier network. Can be used with cloud-init or during other deployment tools.\
# At minimum, the Network ID must be specified to join the specified network. If an API Key is also specified, this will be used to authorize the member (i.e., getting true access and assigned a ZT IP).\
# If the device is already a member but not authorized, running the script specifying an API Key will just authorize the member.\
\
# For usage and prerequisites, see below or run the script with the --help option.\
# CAUTION: curl, jq, and zerotier-one need to be installed for the script to work correctly.\
\
function usage \{\
  cat <<EOFUSAGE\
  This script will automatically join a new device (member) to a ZeroTier network. Can be used with cloud-init or during other deployment tools.\
\
  USAGE: $0 --network=<32charalphanum> --api=<32charalphanum> [ <other options: see below> ]\
\
  OPTIONS:\
    -a=,  --api=\
            (32 digit alphanumeric key) OPTIONAL. Specifies the ZeroTier API Token (account) to authorize the device - i.e., getting true access and assigned a ZT IP.\
            NOTE: If not specified, the device will still be joined to the network but not able to communicate with other devices until authorized by an admin or by running this script with the --api option.\
\
    -u=,  --url=\
            (HTTPS) OPTIONAL. URL to a standalone ZeroTier network controller API (Moon).\
            Default value is https://my.zerotier.com/api as this is the public network controller default configured in every ZeroTier client.\
            NOTE: This argument is only for those who run a standalone ZeroTier network controller.\
\
    -n=, --network=\
            (16 digit alphanumeric key) REQUIRED. The ZeroTier network (Network ID) to join.\
            NOTE: A Network ID must be specified.\
\
    -m=,  --member=\
            (STRING) OPTIONAL. RECOMMENDED. Configures the device member shortname used by this client for the specific ZeroTier network.\
            Default action is to use the unique device Node ID (10-digit alphanumeric) as member shortname. Use this option to set a more recognizable value.\
            NOTE: Name must only be enclosed in quotes (" ") if any spaces are used. Though spaces will be replaced with dashes (-) for DNS compatibility.\
            This setting is an object value stored inside each ZeroTier network. As a client, it is therefore possible to use a different short name inside each network.\
            Joining via the zerotier-cli utility will not configure any shortname and leave an empty value. This can cause problems if pulling data for DNS use.\
\
    -d=,  --description=\
            (STRING) OPTIONAL. RECOMMENDED. Configures the device member description field for this client.\
            NOTE: Description must only be enclosed in quotes (" ") if any spaces are used.\
            This setting is an object value stored inside each ZeroTier network. As a client, it is therefore possible to use a different description field inside each network.\
            Joining via the zerotier-cli utility will not configure any description and leave an empty value.\
\
  PREREQUISITES:\
    APPLICATIONS: zerotier-one, curl, jq\
EOFUSAGE\
\}\
\
# Builtin default values. Do not change these.\
APIKEY=\
NETWORKID=all\
APIURL="https://my.zerotier.com/api"\
SILENT=false\
VERBOSE=false\
MYID=$(zerotier-cli info | cut -d " " -f 3)\
HOSTNAME=$MYID\
DESCRIPTION=\
\
args=()\
while (( $# > 0 )); do\
    arg="$1"\
    arg_key="$\{arg%%=*\}"\
    arg_data="$\{arg#*=\}"\
    case $arg_key in\
        --help|-h)          usage; exit 0               ;;\
        --api|-a)           APIKEY=$\{arg_data\}          ;;\
        --url|-u)           APIURL=$\{arg_data\}          ;;\
        --network|-n)       NETWORKID=$\{arg_data\}       ;;\
        --member|-m)        HOSTNAME=$\{arg_data\}        ;;\
        --description|-d)   DESCRIPTION=$\{arg_data\}     ;;\
    esac\
    shift\
done\
\
# Uncomment and change any of these variables below to override args\
# APIKEY="32xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"\
# NETWORKID="16xxxxxxxxxxxxxx"\
# SILENT=false\
# VERBOSE=false\
# HOSTNAME=$MYID\
# DESCRIPTION=`hostname -s`\
# Uncomment and change any of these variables above to override args\
\
# Normalize runtime arguments\
SILENT=$(echo "$SILENT" | awk '\{print tolower($0)\}')\
VERBOSE=$(echo "$VERBOSE" | awk '\{print tolower($0)\}')\
HOSTNAME=$(echo "$HOSTNAME" | sed 's/ /-/g' | awk '\{print tolower($0)\}')\
\
# Check if arguments are set or dependencies are installed\
[[ ! -x "$(command -v jq)" ]] && \{ echo "Error: jq JSON processor is not installed or in PATH. See https://stedolan.github.io/jq/download/"; exit 1; \}\
[[ ! -x "$(command -v curl)" ]] && \{ echo "Error: curl command-line tool is not installed or in PATH"; exit 1; \}\
[[ -z "$APIKEY" ]] && \{ echo "Error: API Token must be specified."; usage; exit 1; \}\
[[ "$NETWORKID" == all ]] && \{ echo "Error: NETWORK ID not specified."; usage; exit 1; \}\
[[ ! $(echo "$APIKEY" | awk '\{print length\}') == 32 ]] && \{ echo "Syntax Error: API Token can only be a 32-digit alphanumeric value"; exit 1; \}\
[[ ! "$NETWORKID" == all && ! $(echo "$NETWORKID" | awk '\{print length\}') == 16 ]] && \{ echo "Syntax Error: Network ID can only be a 16-digit alphanumeric value"; exit 1; \}\
# End argument check\
\
function zt_member_auth \{\
    JSON=$(curl -s -H "Authorization: Bearer $APIKEY" "$APIURL/network/$NETWORKID/member/$MYID" | jq -c --arg name "$HOSTNAME" --arg description "$DESCRIPTION" '.config.authorized=true | .name=$name | .description=$description')\
    curl -s -o /dev/null -H "Authorization: Bearer $APIKEY" -d "$JSON" "$APIURL/network/$NETWORKID/member/$MYID"\
    # New member - wait for local client to get updated\
    echo -ne "waiting for network auth to register"\
    while [ -z "$(zerotier-cli listnetworks | grep "$NETWORKID" | grep OK)" ]; do echo -ne "."; sleep 1; done\
    echo -ne '\\n'\
\}\
\
# Join or already a member?\
if [ -z "$(zerotier-cli listnetworks | grep "$NETWORKID")" ]; then\
    echo "Not a member... Joining $NETWORKID"\
    zerotier-cli join "$NETWORKID"\
    echo -ne "Waiting for connection to $NETWORKID"\
    while [ -z "$(zerotier-cli listnetworks | grep "$NETWORKID" | grep ACCESS_DENIED)" ]; do echo -ne "."; sleep 1; done\
    echo -ne '\\n'\
    echo "Joined network, but need authentication"\
    if [ -n "$APIKEY" ]; then\
        echo "API Token will be used to authorize $MYID"\
        zt_member_auth\
        MYIP=$(zerotier-cli get "$NETWORKID" ip)\
        echo "Device connected to $NETWORKID with IP $MYIP"\
    fi # Auth new member\
else\
    if [ -n "$APIKEY" ]; then\
        echo "Device already a member of $NETWORKID"\
        echo "API Key will be used to authorize $MYID"\
        zt_member_auth\
        MYIP=$(zerotier-cli get "$NETWORKID" ip)\
        echo "Device connected to $NETWORKID with IP $MYIP"\
        exit 0\
    fi # Auth existing member\
    MYIP=$(zerotier-cli get "$NETWORKID" ip)\
    [[ -z "$MYIP" ]] && \{ echo "Already a member of $NETWORKID but not authorized"; exit; \}\
    echo "Device already a member with IP $MYIP"\
fi # Join member\
\
exit 0\
}
>>>>>>> origin/main
