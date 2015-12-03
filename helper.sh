#!/bin/bash - 

# * Name: helper.sh
# * Description : Helper script for series.rb
# * Author: Nuno Serro
# * Date: 30/11/2009
# * License: This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# * Copyright 2009 Nuno Serro

test -r ~/bin/series/series.conf && echo "#!/bin/bash" > /tmp/series.conf && cat ~/bin/series/series.conf | sed 's/\$//g' | sed 's/HOME/\$HOME/g' >> /tmp/series.conf 
test -r /tmp/series.conf && . /tmp/series.conf

os=$(uname)
arch=$(uname -m)
timestamp=$(date)
hostname=$(hostname)

#######################################################
#			Checks for missing and new		
#######################################################

case "$1" in

	"--new" | "-n" )

		storage_total=$(df -ha $library_location | tail -1 | awk '{print $2}')
		storage_free=$(df -ha $library_location | tail -1 | awk '{print $4}')

		template_beginning="
		<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">
		<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"pt\" lang=\"pt\">
			<head>
				<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">
				<title>TV Shows</title>
				<link href=\"https://www.dropbox.com/static/css/main.css\" rel=\"stylesheet\" type=\"text/css\">
				<link rel=\"shortcut icon\" href=\"https://www.dropbox.com/static/images/favicon.ico\"/>
				<style type=\"text/css\">
		  			.footer, .push {
						height: 4em;
					}
		  		</style>
			</head>
			<body style=\"background-color:#fff\">
				<br/><br/>  
				<div align=\"center\">
					<table>
						<tr><td width=\"350px\">
						<font size=\"2\">
			 				<h4>Episodios em falta:</h4>
		"

		template_midle="<br />
		<h4>Proximos:</h4><p>
		"

		template_end="
		<br /><h4>Links:</h4><p>
		<a href="https://meusitio.ddns.net:25050">Couch Potato</a><p>
		<a href="https://meusitio.ddns.net:20443/transmission/web/">Transmission</a><p>
		<a href="https://dl.dropboxusercontent.com/u/364055/temperatura.html">Temperatura</a><p>
		</font> </td></tr></table> </div> <center> <hr size="1" width="25%"> 
			   		<div class=\"footer\">
				   		<small>
				   			
				   			Ultima Actualizacao: $timestamp<br/>
				   			Storage: $storage_free free / $storage_total total <br/>
				   			Provider: $os $arch<br/>
				   			IP cliente:<script type="text/javascript" src="https://l2.io/ip.js"></script><br />
				   			
				   		</small>
				   	</div>
			   	</center>
			</body>
		</html>
		"

		next=`/home/pi/bin/series/series.rb -nx`
		missing=`/home/pi/bin/series/series.rb -mx`

		echo $template_beginning > /tmp/series.html
		echo -e "$missing" | sed  -e 's/$/<\/p>/' >> /tmp/series.html
		echo $template_midle >> /tmp/series.html
		echo -e "$next" | grep -v "Episode not scheduled" | sed  -e 's/$/<\/p>/' >> /tmp/series.html
		echo $template_end >> /tmp/series.html

		$HOME/bin/dropbox_uploader.sh upload /tmp/series.html /Public/series.html
		
		exit 0
	;;

#######################################################
#			Moves episodes to library		
#######################################################

	"--move" | "-m" )
	
		if [ $# -lt 2 ]; then
				echo "Insuficient arguments. A path must be provided."
				exit 1
		fi

		# If path exists continues
		if [ -d "$2" ]; then

			# If path not empty continues
			if [ "$(ls -A $2)" ]; then
     
				eval log=$log_location"series_moved.log"
				OIFS=$IFS
				IFS=""
				destino=$library_location
				cd $2
				# Move files to root
 				find . -iregex '.*\(srt\|avi\|mkv\|mpg\|mpeg\|mp4\|m4v\|wmv\)' -not -path '*/*ample*/*' -exec mv "{}" . \; 2> /dev/null
		
				echo "################" >> $log
				date +'%d-%m-%Y-%H:%M' >> $log
				echo "################" >> $log
				echo "Lista de ficheiros originais:" >> $log
				ls $2 >> $log
				echo "Extensoes filtradas: *.srt *.avi *.mkv *.mpg *.mpeg *.mp4 *.m4v *.wmv" >> $log
				echo "Comandos utilizados:" >> $log

				for item in *.srt *.avi *.mkv *.mpg *.mpeg *.mp4 *.m4v *.wmv
				do
					# Renames
					eval binary=$binary_location"series.rb"
					novo_nome=`"$binary" -f "$item"` 
					if [ $? != 0 ]
						then
						# Not found. Continues.
					 	continue
					fi
					#mv "$item" $2$novo_nome >> $log

					# Creates folder and moves
					nome_serie=`echo $novo_nome | sed 's/\( - S.*\)//'`
					num_serie=`echo $novo_nome | sed 's/\(.*\) - \(.*\)/\1/' | sed 's/\(.*\) - S//'| sed 's/\0//' | sed 's/E\(.*\)//'`
					mkdir -p $destino"/"$nome_serie"/Season "$num_serie
					echo "mv $2/$novo_nome $destino$nome_serie/Season $num_serie" >> $log
					#mv $2/"$novo_nome" $destino$nome_serie"/Season "$num_serie
					mv $item $destino$nome_serie"/Season "$num_serie/"$novo_nome"
					
					# Notifies
					$HOME/bin/boxcar.sh "$hostname" "Series" "Episódio arrumado: $novo_nome"

				done
				
				IFS=$OIFS
				$HOME/bin/dropbox_uploader.sh upload $log /log/series_moved.log
				xbmc-send -a "UpdateLibrary(video)" >> /dev/null 2>&1

			fi
		fi
		# Actualiza "base de dados"
		eval list=$log_location"lista.log"
		command /bin/ls -1R $destino > $list

		#Remove torrents que estejam completos
		completos=`transmission-remote localhost:$transmission_port -n $transmission_credentials -l | grep 100% | awk '{ print $1 }'`
		if [ "$completos" == "" ]; then 
			exit 0
		fi
		for var in "${completos[@]}"
		do
			transmission-remote localhost:$transmission_port -n $transmission_credentials -t ${var} -r
		done
		exit 0
	;;

#######################################################
#						Help		
#######################################################

	"--help" | "-h" )

		echo "Usage:
       helper.rb [options] <path>
where [options] are:
  -n, --new        Checks for new and missing episodes
  -m, --move       Move episodes in <path> to library"

		exit 0
	;;

	* )
	
		echo "Error: need at least one option."
		echo "Try --help for help."
		exit 1	
	;;

esac

exit 0