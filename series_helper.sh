#!/bin/bash - 

# * Name: series_helper.sh
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

# Load config
test -r ~/bin/series/series_config && . ~/bin/series/series_config

OS=$(uname)
ARCH=$(uname -m)
TIMESTAMP=$(date)
HOSTNAME=$(hostname)
STORAGE_TOTAL=$(df -ha $pasta_series | tail -1 | awk '{print $2}')
STORAGE_FREE=$(df -ha $pasta_series | tail -1 | awk '{print $4}')

template_inicio="
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">
<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"pt\" lang=\"pt\">
	<head>
		<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">
		<title>TV Shows</title>
		<link href=\"http://www.dropbox.com/static/css/main.css\" rel=\"stylesheet\" type=\"text/css\">
		<link rel=\"shortcut icon\" href=\"http://www.dropbox.com/static/images/favicon.ico\"/>
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

template_fim="

				</font>
	   		</td></tr></table>
	   	</div>
	   	<center>
	   		<a href=\"https://www.dropbox.com/referrals/NTM2NDA1NTk\"><img id=\"errorimage\" src=\"http://www.dropbox.com/static/images/psychobox.png\"/></a> 
		   	<div class=\"footer\">
		   		<small>
		   			
		   			Ultima Actualizacao: $TIMESTAMP<br/>
		   			Storage: $STORAGE_FREE free / $STORAGE_TOTAL total <br/>
		   			Provider: $OS $ARCH<br/>
		   		</small>
		   	</div>
	   	</center>
	</body>
</html>
"


# Funcao falta
# Argumentos de entrada: nome da serie
#                        -s chama funcao series_torrent.sh e saca torrents com magnet link
#                        -html retorna com tags html

function falta {
	
	$bin_path/series.rb -u $1 | sed 's/\(.*\) - \(.*\)/\1/' > $HOME/.temp.out
	num_serie=`$bin_path/series.rb -u $1 | sed 's/\(.*\) - \(.*\)/\1/' | sed 's/\(.*\) - S//'| sed 's/\0//' | sed 's/E\(.*\)//'`

	# Processamento da entrada
	in=`echo $1 | sed 's/_/ /g'`

	testa=`cat $pasta_logs/lista.log | grep -f $HOME/.temp.out`
	if [ "" != "$testa" ]
	then
 		sleep 0
	else
		# Nao tem o ultimo Episódio, vai fazer print dos que faltam.

		ultimo_disponivel=`cat $HOME/.temp.out | sed 's/\(.*\) - S[0-9][0-9]E//' | grep [0-9] | sed '1s/^[0]//'`
		ultimo_existente=`cat $pasta_logs/lista.log | grep "$in" | tail -1 | sed 's/\(.*\) - \(.*\)/\1/' | sed 's/\(.*\) - S[0-9][0-9]E//' | sed '1s/^[0]//'`

		#Se ultimo existente tiver numero superior ao ultimo disponivel, significa que o utltimo existente e da serie anterior, logo coloca ultimo existente a 0
		if [ "$ultimo_existente" == "" ]
		then
			ultimo_existente=0
		fi
 
		if [ $ultimo_existente -gt $ultimo_disponivel ]
		then
			ultimo_existente="0"
		fi

		# Testa se tem Episódio duplo (&). Considera apenas o 2o Episódio. 
		char_meio=`echo $ultimo_existente |  grep "&"`
		if [ "" != "$char_meio" ]
		then
			ultimo_existente=`cat $pasta_logs/lista.log | grep "$in" | tail -1 | sed 's/\(.*\) - \(.*\)/\1/' | sed 's/\(.*\) - S[0-9][0-9]E//' | sed 's/\(.*\)&//'| sed '1s/^[0]//'`
	  	fi
	  	i=$((ultimo_existente+1)) 
	  	while [ "$i" != "$ultimo_disponivel" ]
	  	do
			falta=`$bin_path/series.rb -s $1-s$num_serie-e$i`
	    	if [[ "-html" == $2 ]]
	    	then
	    		falta=`$bin_path/series.rb $1-s$num_serie-e$i`
	    	fi
	    	if [ "-s" == $2 ]
	    	then
	    		# Se recebeu argumento -s chama secçao de download
 				$bin_path/series_helper.sh -d "$falta"
	    	else
	      		if [[ "-html" == $2 ]]
	      		then
					echo "$falta</p>"
	      		else
					echo $falta
	      		fi
	    	fi  
	    	i=$((i+1))
	  	done
	  	falta=`$bin_path/series.rb -s $1-s$num_serie-e$ultimo_disponivel`
	 	if [[ "-html" == $2 ]]
	  	then
	    	falta=`$bin_path/series.rb $1-s$num_serie-e$ultimo_disponivel`
	  	fi
	  	if [ "-s" == $2 ]
	  	then
			$bin_path/series_helper.sh -d "$falta"
	    	# torrent=`$bin_path/series_torrent.rb $falta`
	    	# open $torrent
	    	# echo $torrent
	  	else
	    	if [[ "-html" == $2 ]]
	    	then
	      		echo "$falta</p>"
	    	else
	      		echo $falta
	    	fi
	  	fi
	fi

	rm $HOME/.temp.out

}


case "$1" in

#######################################################
#			--proximos	
#######################################################

	"--proximos" | "-p" )

		for item in ${series[*]}
		do
	    	CMD=`$bin_path/series.rb -ps $item`
			if [[ $CMD != *ERRO:* ]]
			then
		 		if [[ $2 == "-html" ]]
		 		then
		   			echo "$CMD</p>";
		 		else
		   			echo "$CMD";
		 		fi
	 		fi
		done
	exit    
	;;

#######################################################
#			--download	
#######################################################

	"--download" | "-d" )

		if [ $# -lt 2 ]; then
			echo "ERRO: Argumentos insuficientes"
			exit 1
		fi

		search=`echo $2+PublicHD | sed 's/-/+/g'`
		info=`echo $search | grep -o "S[0-9][0-9]E[0-9][0-9]"`
		wget --quiet "http://thepiratebay.se/search/$search" -O $HOME/.series_link
		# If there are No hits for PublicHD, tries standard definition
		line=$(grep "No hits." $HOME/.series_link)
		if [ $? -eq 0 ]
   		then
    		search=`echo $2 | sed 's/-/+/g'`
			info=`echo $search | grep -o "S[0-9][0-9]E[0-9][0-9]"`
			wget --quiet "http://thepiratebay.se/search/$search" -O $HOME/.series_link
		fi 
		magnet=$(cat $HOME/.series_link | grep $info | grep -om 1 "magnet:.*\" title=\"Down" | sed -e 's/\" title=\"Down//')
		if [ "$OS" == "Darwin" ]; then
			torrent_bin="open /Applications/Transmission.app/"
		else
			$HOME/bin/boxcar.sh "$HOSTNAME" "Series" "Download iniciado: $2"
			xbmc-send -a "Notification(Series,Download iniciado: $2)"
			torrent_bin="transmission-remote localhost:$transmission_port -n $transmission_credentials -w $transmission_dlpath -a"
		fi
		$torrent_bin $magnet
		#open /Applications/Transmission.app/ $magnet
	exit 0 
	;;

#######################################################
#			--arruma	
#######################################################

	"--arruma" | "-a" )
		# Renomeia correctamente Episódios em $2 e move-os para $destino
		# com uma hierarquia: ../Nome de Serie/Season X/Episódio
		
		if [ $# -lt 2 ]; then
			echo "ERRO: Argumentos insuficientes"
			exit 1
		fi

		# Se pasta existir continua
		if [ -d "$2" ]; then

			# Se nao estiver vazia continua
			if [ "$(ls -A $2)" ]; then
     

				log="$pasta_logs/series_moved.log"

				OIFS=$IFS
				IFS=""

				destino=$pasta_series
				cd $2
				
				#Move ficheiros para a raiz e apaga pastas
 				find . -iregex '.*\(avi\|mkv\|mpg\|mpeg\|mp4\|m4v\|wmv\)' -exec mv "{}" . \; 2> /dev/null
 				find . -type d -exec rm -rf "{}" \; 2> /dev/null

				ficheiros=*
				
				echo "################" >> $log
				date +'%d-%m-%Y-%H:%M' >> $log
				echo "################" >> $log
				echo "Lista de ficheiros originais:" >> $log
				ls $2 >> $log
				echo "Extensoes filtradas: *.avi *.mkv *.mpg *.mpeg *.mp4 *.m4v *.wmv" >> $log
				echo "Comandos utilizados:" >> $log

				for item in $ficheiros
				do
					#Renomeia
					novo_nome=`$bin_path/series.rb "$item"` 
					if [ $? != 0 ]
					then
						# Não encontrou serie, talvez seja filme
						echo "mv $2/$item $pasta_movies/" >> $log
						mv $2"/""$item" $pasta_movies"/"
						continue
					fi
					mv "$item" $2"/""$novo_nome" >> $log

					#Cria pasta e move
					nome_serie=`echo $novo_nome | sed 's/\( - S.*\)//'`
					num_serie=`echo $novo_nome | sed 's/\(.*\) - \(.*\)/\1/' | sed 's/\(.*\) - S//'| sed 's/\0//' | sed 's/E\(.*\)//'`
					
					mkdir -p $destino"/"$nome_serie"/Season "$num_serie
					echo "mv $2/$novo_nome $destino/$nome_serie/Season $num_serie" >> $log
					mv $2"/""$novo_nome" $destino"/"$nome_serie"/Season "$num_serie
					$HOME/bin/boxcar.sh "$HOSTNAME" "Series" "Episódio arrumado: $novo_nome"
					xbmc-send -a "Notification(Series,Episódio arrumado: $novo_nome)"

				done
				IFS=$OIFS
				$HOME/bin/dropbox_uploader.sh upload $pasta_logs/series_moved.log /log/series_moved.log
				xbmc-send -a "UpdateLibrary(video)" >> /dev/null 2>&1

			fi
		fi
		# Actualiza "base de dados"
		command /bin/ls -1R $pasta_series > $pasta_logs/lista.log

		Remove torrents que estejam completos
		completos=`transmission-remote localhost:$transmission_port -n $transmission_credentials -l | grep 100% | awk '{ print $1 }'`
		for var in "${completos[@]}"
		do
			transmission-remote localhost:$transmission_port -n $transmission_credentials -t ${var} -r
		done
		
	exit 0 
	;;


#######################################################
#			--falta	--saca
#######################################################

"--falta" | "-f" | "--saca" | "-s" )



	#cp  $HOME/bin/series/series_template_inicio.html  $HOME/.temp.html
	echo $template_inicio > $HOME/.temp.html

	flag=0
	for item in ${series[*]}
	do

		CMD=`falta $item $1`

  		CMD_html=`falta $item "-html"`

  		if [ "" != "$CMD" ]
  		then
		    echo "$CMD"
		    echo "$CMD" > $HOME/.temp.out
		    testa_falta=`cat $pasta_logs/falta.log | grep -f $HOME/.temp.out`
		    if [ "" = "$testa_falta" ]
	    	then
			    #echo "do shell script \"/usr/local/bin/growlnotify -d 6 -s -t 'Script Series' -m 'Novo Episódio: $CMD'\"" > $HOME/bin/series/growl.osa
			    #existe=`command -v osascript`
			    if [ "$existe" != "" ]; then
			    	echo "bla" > /dev/null
			    	#osascript $HOME/bin/series/growl.osa > /dev/null
			    else
			    	# Não é OSX usa script boxcar.sh
			    	$HOME/bin/boxcar.sh "$HOSTNAME" "Series" "Novo Episódio: $CMD"
			    	#xbmc-send -a "Notification(Series,Novo Episódio: $CMD)"
			    fi
			    echo $CMD >> $pasta_logs/falta.log
			    rm $HOME/.temp.out
	    	fi
	    	echo "<p>$CMD_html</p>" >> $HOME/.temp.html
	    	flag=1
	  	fi
	done

	if [ $flag == 0 ]
	then
	  	echo "Up to date"
	  	echo "<p>Nao ha episodios em falta.</p>" >> $HOME/.temp.html
	  	echo "<br />">> $HOME/.temp.html
	  	echo "<h4>Proximos:</h4><p>" >> $HOME/.temp.html
	  	$HOME/bin/series/series_helper.sh -p -html>> $HOME/.temp.html
	  	#cat $HOME/bin/series/series_template_fim.html >> $HOME/.temp.html
	  	echo $template_fim >> $HOME/.temp.html
	  	if [ -s $ficheiro_html ];then
	    	diferenca=`diff $ficheiro_html $HOME/.temp.html`
	  	else
	    	touch $ficheiro_html
	    	diferenca=`diff $ficheiro_html $HOME/.temp.html`
	  	fi
	  	if [ "" = "$diferenca" ]
	  	then
	    	rm $HOME/.temp.html
	  	else
	    	cp $HOME/.temp.html $ficheiro_html
	    	rm $HOME/.temp.html
	  	fi
		if [ "$ARCH" == "armv6l" ]; then
		  	$HOME/bin/dropbox_uploader.sh upload $ficheiro_html /Public/series.html
		  	$HOME/bin/dropbox_uploader.sh upload $pasta_logs/falta.log /log/falta.log
		  	$HOME/bin/dropbox_uploader.sh upload $pasta_logs/lista.log /log/lista.log
		fi
	  	exit 0
	else
		echo "<h4>Proximos:</h4><p>" >> $HOME/.temp.html
		$HOME/bin/series/series_helper.sh -p -html>> $HOME/.temp.html
		#cat $HOME/bin/series/series_template_fim.html >> $HOME/.temp.html 
		echo $template_fim >> $HOME/.temp.html

		if [ -s $ficheiro_html ];then
	    	diferenca=`diff $ficheiro_html $HOME/.temp.html`
	  	else
	    	touch $ficheiro_html
	    	diferenca=`diff $ficheiro_html $HOME/.temp.html`
	  	fi
	  	if [ "" = "$diferenca" ]
	  	then
	    	rm $HOME/.temp.html
	  	else
	    	cp $HOME/.temp.html $ficheiro_html
	    	rm $HOME/.temp.html
	  	fi
	  	if [ "$ARCH" == "armv6l" ]; then
		  	$HOME/bin/dropbox_uploader.sh upload $ficheiro_html /Public/series.html
		  	$HOME/bin/dropbox_uploader.sh upload $pasta_logs/falta.log /log/falta.log
		  	$HOME/bin/dropbox_uploader.sh upload $pasta_logs/lista.log /log/lista.log
		fi
	  	exit 1
	fi

;;

#######################################################
#		--lista
#######################################################

	"--lista" | "-l" )

	echo "Series seguidas:
"${series[*]}
	exit	
	;;

#######################################################
#		--update
#######################################################

	"--update" | "-u" )

	command /bin/ls -1R $pasta_series > $pasta_logs/lista.log
	echo "Lista actualizada"
	exit	
	;;

#######################################################
#		input inválido	
#######################################################

	* )

		echo "Opcao inválida
Utilizacao: series_helper.sh OPCAO
	-u, --update 		actualiza lista de Episódios existentes
	-f, --falta 		mostra Episódios em falta
	-p, --proximos	 	mostra proximos Episódios
	-a, --arruma [CAMINHO]	arruma Episódios que se encontrem em [CAMINHO]
	-l, --lista	 	mostra lista de series que são seguidas
	-s, --saca 		faz download de Episódios em falta
	-d, --down [EPISODIO]	envia para cliente de torrent magnet link referente a [EPISODIO]"
		exit 1	
	;;

esac

exit 0
