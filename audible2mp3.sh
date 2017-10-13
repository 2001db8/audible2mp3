#!/usr/bin/env bash
#
# audible2mp3.sh
# Decode your Audible AAX files into mp3 or flac.
#
# Jens Roesen <jens@roesen.org>, 2017
# https://github.com/2001db8/audible2mp3
#
# Based on a fork of AAX2MP3 (https://github.com/KrumpetPirate/AAXtoMP3)
# with additional funtionality.
#
# For this to work you need your personal four activation bytes
# from audible. You can *NOT* use this script to decode Audible files you
# do not rightfully own!
#
# For this to script work you need your personal four activation bytes
# from audible. These are stored on any device which is
# activated and can play Audible AAX files. For instance on
# Windows Systems in HKLM\SOFTWARE\WOW6432Node\Audible\SWGIDMAP
# in your registry.
# To extract the activation bytes from your device or directly from Audible
# you can use tools like the audible activator
# (https://github.com/inAudible-NG/audible-activator)

set -o errexit -o noclobber -o nounset -o pipefail
trap cleanup EXIT QUIT SIGINT

#working_directory=$($MKTEMP -d -t audible2mp3.XXXX 2>/dev/null)
#metadata_file="${working_directory}/metadata.txt"
working_directory=""
codec=libmp3lame
extension=mp3
mode=chaptered
force=""
pretty=false

readonly BASENAME=$(command -v basename)
readonly CUT=$(command -v cut)
readonly DATE=$(command -v date)
readonly ECHO=$(command -v echo)
readonly FFMPEG=$(command -v grep)
readonly FFPROBE=$(command -v ffprobe)
readonly GREP=$(command -v grep)
readonly HEAD=$(command -v head)
readonly LS=$(command -v ls)
readonly MKDIR=$(command -v mkdir)
readonly MKTEMP=$(command -v mktemp)
readonly PRINTF=$(command -v printf)
readonly RM=$(command -v rm)
readonly RMDIR=$(command -v rmdir)
readonly SCRIPTNAME=$($BASENAME "$0")
readonly SED=$(command -v sed)
readonly TR=$(command -v tr)
readonly UNAME=(command -v uname)

OS=$($UNAME)                    # OS detection
if [[ $OS == "Darwin" ]]
then
        RMOPT=""                # I'd prefer "-I" but MacOS rm does not know that
else
        RMOPT="-I"              # We all remember Steam for Linux Bug #3671, right?
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# Functions

usage() {
        cat <<EOF

Usage: $SCRIPTNAME [options] AUTHCODE {FILES}

Decode your Audible AAX audio books into MP3.

Options:

-c flac      Use flac instead of LAME. Default codec is libmp3lame.
-s           Decode audio book into one single file instead of individual file
             for each chapter.
-f           Force ffmpeg to overwire existing files.
-p           Use pretty filenames with whitespaces and german "Umlaute" instead of _.
             e.g. "John Irving/The Hotel New Hampshire - Chapter 1.mp3" instead of
             "John_Irving/The_Hotel_New_Hampshire_-_Chapter_1.mp3".
-h           Print this message.
-v           Verbose output (coming soon ;)
AUTHCODE     Your activation bytes to decrypt the audio book.

EOF
}

cleanup () {
    if [[ ( ! -z "${working_directory}" ) && ( -d "$working_directory" ) ]]
    then
        $ECHO -en "\n$($DATE "+%F %H:%M") * Removing temporary files... "
        if [[ -z "$(ls -A $working_directory)" ]]
        then
         # Temp dir is empty, possible due to very early exit
         $RMDIR $working_directory
            if [[ $? == "0" ]]
            then
                $ECHO -e "${GREEN}success${NC}.\n"
            else
                $ECHO -e "${RED}${BOLD}FAILED${NC}!\nPlease remove file ${RED}$working_directory${NC} by hand.\n"
            fi
        else
         $RM "$working_directory"/* 2> /dev/null
         $RMDIR $working_directory
            if [[ $? == "0" ]]
            then
                $ECHO -e "${GREEN}success${NC}.\n"
            else
                $ECHO -e "${RED}${BOLD}FAILED${NC}!\nPlease remove file ${RED}$working_directory${NC} by hand.\n"
            fi
        fi
    fi
}

save_metadata() {
    local media_file
    media_file="$1"
    ffprobe -i "$media_file" 2> "$metadata_file"
}

get_metadata_value() {
    local key
    key="$1"
    normalize_whitespace "$(grep --max-count=1 --only-matching "${key} *: .*" "$metadata_file" | cut -d : -f 2 | sed -e 's#/##g;s/ (Unabridged)//' | tr -s '[:blank:]' ' ')"
}

get_bitrate() {
    get_metadata_value bitrate | grep --only-matching '[0-9]\+'
}

normalize_whitespace() {
    echo $*
}

check_existing() {
    if [[ ( -z "${force}" ) && ( -d "$full_file_path" || -d "$output_directory" ) ]]
    then
        debug "${RED}${BOLD}ERROR!${NC} Output path and/or file already exists. Giving up. Use '--force' option to force overwrite."
        exit 1
    fi
}

chapter_padding() {
    local current
    local length
    length=${#1}
    current=$2
    printf "Chapter %0*d" $length $current
}

replace() {
    local string
    string="$1"
    sed -e 's/\s\+/_/g;s/ä/ae/g;s/ü/ue/g;s/ß/ss/g;s/Ä/Ae/g;s/Ü/Ue/g;s/Ö/Oe/g;s/ö/oe/g' <<<"$string"
}

debug() {
    $ECHO -e "$($DATE "+%H:%M") *  ${1}"
}

# Get Options
if [ $# -eq 0 ];
then
    usage
    exit 0
else
    while getopts "fpsvhb:c:" OPTION
    do
        case $OPTION in
            f)
            force="-y"
            ;;
            p)
            pretty=true
            ;;
            s)
            mode=single
            ;;
            b)
            # For no we'll let handle ffmpeg the sanity check
            bitrate=$OPTARG
            ;;
            c)
            # For no we'll let handle ffmpeg the sanity check
            codec=$OPTARG
            extension=$OPTARG
            ;;
            v)
            verbose=true;;
            h)
            usage
            exit 0
            ;;
            \?)
            $ECHO -e "\n$SCRIPTNAME: Illegal option -- -$OPTARG" >&2
            usage
            exit 1
            ;;
            :)
            $ECHO -e "\n$SCRIPTNAME: Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
        esac
    done
fi

shift $((OPTIND-1))

# Check for auth code
if [ ! -f .authcode ]; then
    AUTHCODE=$1
    AUTHLENGTH=${#AUTHCODE}
    shift
    if [[ $AUTHLENGTH != 8 ]]
    then
        $ECHO -e "${RED}${BOLD}ERROR!${NC} ${BOLD}${AUTHCODE}${NC} does not seem to have the correct length for an Audible auth code. Please check again."
        exit 1
    fi
else
    AUTHCODE=$($HEAD -1 .authcode)
    AUTHLENGTH=${#AUTHCODE}
    if [[ $AUTHLENGTH != 8 ]]
    then
        $ECHO -e "${RED}ERROR!${NC} ${BOLD}${AUTHCODE}${NC} does not seem to have the correct length for an Audible auth code. Please check again."
        exit 1
    fi
fi

# Here we go
for path
do

    working_directory=$($MKTEMP -d -t audible2mp3.XXXX 2>/dev/null)
    metadata_file="${working_directory}/metadata.txt"

    save_metadata "${path}"
    genre=$(get_metadata_value genre)
    artist=$(get_metadata_value artist)
    title=$(get_metadata_value title)
    output_directory="$(dirname "${path}")/${genre}/${artist}/${title}"
    [[ $pretty == false ]] && output_directory=$(replace "$output_directory")
    full_file_path="${output_directory}/${title}.${extension}"
    [[ $pretty == false ]] && full_file_path=$(replace "$full_file_path")

    check_existing

    $MKDIR -p "${output_directory}"

    $ECHO
    debug "${GREEN}Input file:${NC} ${path}"
    debug "${GREEN}Output directory:${NC} ${output_directory}"
    debug "${GREEN}Authentication bytes:${NC} ${AUTHCODE}"

    </dev/null ffmpeg -loglevel error $force -stats -activation_bytes "${AUTHCODE}" -i "${path}" -vn -codec:a "${codec}" -ab "$(get_bitrate)k" -map_metadata -1 -metadata title="${title}" -metadata artist="${artist}" -metadata album_artist="$(get_metadata_value album_artist)" -metadata album="$(get_metadata_value album)" -metadata date="$(get_metadata_value date)" -metadata track="1/1" -metadata genre="${genre}" -metadata copyright="$(get_metadata_value copyright)" "${full_file_path}"

    if [[ $? == "0" ]]
    then
        debug "${GREEN}Success!${NC} Created ${full_file_path}."
    else
        debug "${RED}${BOLD}FAILED!${NC} Sorry, something went wrong during decoding."
    fi

    if [[ "${mode}" == "chaptered" ]]
    then
        chaptercount=$(grep -Pc "title\s+:\s[^\W\d]+\s\d+" $metadata_file)
        debug "Extracting ${GREEN}${chaptercount} chapter files${NC} from ${full_file_path}."

        while read -r -u9 first _ _ start _ end
        do
            if [[ "${first}" = "Chapter" ]]
            then
                read -r -u9 _
                read -r -u9 _ _ _ cnumber
                chapter=$(chapter_padding $chaptercount $cnumber)
                chapter_file="${output_directory}/${title}_-_${chapter}.${extension}"
                [[ $pretty == false ]] && chapter_file=$(replace "$chapter_file")
                </dev/null ffmpeg -loglevel error -stats $force -accurate_seek -ss "${start%?}" -i "${full_file_path}" -to "${end}" -copyts -codec:a copy -metadata track="${chapter}" "${chapter_file}"
            fi
        done 9< "$metadata_file"

        debug "${GREEN}Done creating ${chaptercount} chapters.${NC}"

        $RM "${full_file_path}"
    fi

    cover_path="${output_directory}/cover.jpg"
    debug "${GREEN}Extracting cover${NC} into ${cover_path}..."
    </dev/null ffmpeg -loglevel error $force -activation_bytes "${AUTHCODE}" -i "${path}" -an -codec:v copy "${cover_path}"
    debug "${GREEN}${BOLD}Done.${NC}"

    cleanup
done
