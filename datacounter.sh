#!/bin/bash

#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

#    Copyright 2011 Janos Mattyasovszky <matya at sch.bme.hu>

function showusage() {
	echo "
Usage: 
 $0 <options>
   Options are:
    [-i|--input]  <file>  Input is read from filename
    [-o|--output] <file>  Output is written to filename
    [-t|--time]   <n>     Refresh status every second
    [-q|--quiet]          Do not display anything, be silent
    [-c|--cleanup]        Remove status after a successfull finish
    [-s|--size]           Use provided size in bytes to calculate %

 -> Time can be any value, that is accepted by 'sleep'
 -> Size can be only positive and integer
 -> Data is not corrupted by specifying smaller/bigger values, than
    the amount of data that comes from the input.
 -> If no input/output file option is specified, stdin/out is used.
 -> If input file is specified, stdin is discarded.
 -> Options overwrite the previous values
" >&2
	exit 255
}

if ( tty >/dev/null && [ $# -eq 0 ]); then
	showusage
fi

# We assign fd3 to stdout and fd4 to stdin for later use with dd
exec 3>&1
exec 4<&0

# We assign stdout to stderr, to make sure everything is displayed on stderr
# (Note, that this does not affect fd3, this does not re-redirect it)
exec 1>&2

# Parse up command line options
REFRESH_TIME=1
CLEANUP=0
SILENT=0
SIZE=-1
while [ -n "$1" ]; do
	OPT="$1"
	shift
	case "${OPT}" in
		-o|--output)
			FILE="$1"
			[ -z "${FILE}" ] && showusage
			touch "${FILE}" 2> /dev/null || {
				echo "ERROR: Can not create output file '${FILE}'";
				exit 1;
			}
			# We should write to a file instead of stdout, so redirect fd3 to file
			exec 3> ${FILE}
			shift
			;;
		-i|--input)
			FILE="$1"
			[ -z "${FILE}" ] && showusage
			[ -r "${FILE}" ] || {
				echo "ERROR: File '${FILE}' does not exist or no permission to read"; 
				exit 1;
			}
			[ -f "${FILE}" ] && SIZE=$(stat -c %s ${FILE}) || SIZE=-1
			# We should read from a file instead of stdin, so redirect file to fd4
			exec 4< ${FILE}
			shift
			;;
		-s|--size)
			SIZE="${1}"
			shift
			(( SIZE + 0 )) 2> /dev/null || showusage
			;;
		-t|--time)
			[ -z "$1" ] && showusage
			REFRESH_TIME="$1"
			shift
			;;
		-c|--cleanup)
			CLEANUP=1
			;;
		-q|--quiet)
			exec 1>/dev/null
			SILENT=1
			;;
		*)
			showusage;
			;;
	esac
done

# To have the errorcode of dd if it fails
set -o pipefail

# 1) We redirect stdin from fd4
# 2) We redirect stderr to stdout
# 3) We redirect stdout to fd3 (note that stderr ist still on stdout, not fd3!)
# 4) Finally we close fd3 and fd4, so awk does not inherit them (looks better in /proc/)
# The order is important, since the fd's count overwrite each other
dd 0<&4 2>&1 1>&3 3>&- 4>&- | ( [[ $SILENT -eq 1 ]] || awk -v PID=$(pgrep -P $$ dd) -v TIME=${REFRESH_TIME} -v SIZE=${SIZE} 3>&- 4>&- '
	BEGIN { 
		hum[1024^3]="GB";
		hum[1024^2]="MB";
		hum[1024^1]="KB";
		hum[1024^0]="bytes";
		EXITCODE=0;
		print "kill -s 10 " PID " 2> /dev/null" | "sh";
	}
	function clean() {
		printf "                           \r";
	}
	/records/ { next; }
	/byte/ {
		size=$1
		speed=$(NF-1) " " $NF

		clean();
		if (size == 0) {
			printf " [ Waiting for data ] ";
		} else {
			for (x=1024^3; x>=1; x/=1024) { 
				if (size >= x) {
					if (SIZE > -1) {
						printf " [ Transferred %.3f %s (%.2f%%) with %s ] ",size/x, hum[x], size/SIZE*100, speed;
					} else {
						printf " [ Transferred %.3f %s with %s ] ",size/x, hum[x], speed;
					}
					break;
				}
			}
		}
		fflush();
		print "sleep " TIME "; kill -s 10 " PID " 2> /dev/null" |& "sh";
		next;
	}
	{ ERROR=sprintf("\nERROR: %s",$0); EXITCODE=1; }
	END {
		close("sh");
		if (EXITCODE==1)
			printf ERROR;
		exit; # EXITCODE;
	}
' )
EXITCODE=$?

# Should we leave the progressbar and write out a newline, or clear up with
# a carrige return, to allow the next output to overwrite the status bar...
[ $CLEANUP -eq 1 ] && printf "\r" || echo ""

exit ${EXITCODE}

