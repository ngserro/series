#!/usr/bin/ruby -KU

=begin
  * Name: series.rb
  * Description : series - TV Show tracker   
  * Author: Nuno Serro
  * Date: 30/10/2009
  * License: This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

  * Copyright 2009 Nuno Serro
=end

require 'open-uri'
require 'date'
require 'net/http'
require 'socket'
require 'smarter_csv'
require 'amatch'

include Amatch

# TODO:
# --stash: stash the downloaded episodes in the library
# --download: download episode
# --update dropbox file


######## CONFIGURATIONS #########

$library_location="/media/ELEMENTS/TV_Shows/"
$tmp_location="/tmp/"
$use_notifications=true


######## START FUNCTIONS #########

# Checks if internet conection exists
def internet_connection?(url)
	uri = URI.parse(url)
	response = nil
	begin
		Net::HTTP.start(uri.host, uri.port) { |http|
			response = http.head(uri.path.size > 0 ? uri.path : "/")
		}
		return true  
	rescue SocketError => details
	   return false
	end 
end

# Returns hash with TV show information, exits otherwise
def get_show (name)

	# Remove all non char from name
	name.gsub!(/\W/,'')

	# Check myshows
	# testa se o local tem a série
	if File.exist?($tmp_location+'myshows.txt') == true
		
	end
	# se sim define o ficheiro como o myshows, senão define como o allshows

	# Index file doesnt exist and we are offline :(
	if File.exist?($tmp_location+'allshows.txt') == false and $offline=="No internet connection."
		puts "No index file and no internet connection."
		exit 4
	end

	# Index file doesnt exist, but we are online. Download to file and parse
	if File.exist?($tmp_location+'allshows.txt') == false and $offline!="No internet connection."
		open("http://epguides.com/common/allshows.txt") { |io| $html_csv = io.read }
		File.open($tmp_location+'allshows.txt', 'w') {|f| f.write($html_csv) }
	end

	# Read file and create array of hashes
	file = File.open($tmp_location+'allshows.txt', :encoding => 'Windows-1252')
	shows_list = SmarterCSV.process(file)

	# Fuzzy search. If not found updates file and if still not found, removes "The" from name
	fuzzy_test = JaroWinkler.new(name)
	search_show=(shows_list.detect {|show| fuzzy_test.match(show[:directory].to_s) > 0.94})
	if search_show == nil then
		name=name.downcase.gsub("the","")
		fuzzy_test = JaroWinkler.new(name)
	end
	search_show=(shows_list.detect {|show| fuzzy_test.match(show[:directory].to_s) > 0.94})

	if search_show == nil then
		puts "TV Show not found."+$offline
		exit 6
	else
		return search_show
	end
end

# Returns array of hashes with episode information for a given show
def get_episodes(show,mode)

	link = "http://epguides.com/common/exportToCSV.asp?rage="+show[:tvrage].to_s.chomp
	filename=$tmp_location+show[:tvrage].to_s+".txt"

	# Episode file doesnt exist and we are offline :(
	if File.exist?(filename) == false and $offline=="No internet connection."
		puts "No episode file and no internet connection."
		exit 5
	end

	# Episode file doesnt exist, but we are online. Download to temp file and parse episode information
	if File.exist?(filename) == false and $offline!="No internet connection."
		open(link) { |io| $html_csv = io.read }
		File.open(filename, 'w') {|f| f.write("number"+$html_csv.match(/number(.*)<\/pre>/m)[1]) }
	end

	# Episode file exists, but doesnt have necessary info. Download new file if online
	if mode=="download" and $offline!="No internet connection." then
		open(link) { |io| $html_csv = io.read }
		File.open(filename, 'w') {|f| f.write("number"+$html_csv.match(/number(.*)<\/pre>/m)[1]) }
	end

	# Read file and create array of hashes to return
	file = File.open(filename)
	episodes_list = SmarterCSV.process(file)

	return episodes_list

end

# Returns missing episodes in library
def missing(show)
	# Get last existing and parse information
	#cmd = "/bin/ls -1R "+$library_location+" | grep -i \""+show+" - \" | tail -1"
	cmd="cat /Users/nserro/Dropbox/log/lista.log | grep -i \""+show[:title]+" - \" | tail -1"
	last_existing = `#{cmd}`

	# Get file TV show season and episode number
	season=last_existing.scan(/[sS]\d+/)[0].scan(/\d+/)
	episode_num=last_existing.scan(/[eE]\d+/)[0].scan(/\d+/)
	episodes_list=get_episodes(show,"local")
	last_existing_info=(episodes_list.find {|episode| episode[:special?]=="n" and (episode[:episode] == episode_num[0].to_i and episode[:season] == season[0].to_i)})
	search_episode=(episodes_list.select {|episode| episode[:special?]=="n" and ( Date.parse(episode[:airdate]) > Date.parse(last_existing_info[:airdate]) and Date.parse(episode[:airdate]) < Date.today)})
	
	return search_episode
end

# Print episode
def output(show,episode)
	# Print output
	for i in 0...episode.length do
		# If it's a new episode sends notification using boxcar.sh
		if episode[i] != nil and $use_notifications==true and (Date.today-Date.parse(episode[i][:airdate])).to_i.between?(0, 1) then
			cmd="boxcar.sh "+Socket.gethostname+" Series "+"\"Novo Episódio: #{show[:title]} - S#{episode[i][:season].to_s.rjust(2,'0')}E#{episode[i][:episode].to_s.rjust(2,'0')}\""
			`#{cmd}`
		end
		if $short == 0 and episode[i] != nil then
			puts show[:title]+" - S"+episode[i][:season].to_s.rjust(2,'0')+"E"+episode[i][:episode].to_s.rjust(2,'0')+" - "+episode[i][:title]+", "+Date.parse(episode[i][:airdate]).strftime("%A, %d %b %Y").to_s
		elsif episode[i] != nil
			puts show[:title]+" - S"+episode[i][:season].to_s.rjust(2,'0')+"E"+episode[i][:episode].to_s.rjust(2,'0')+", "+Date.parse(episode[i][:airdate]).strftime("%a, %d %b").to_s
		end
	end
end

# Download magnet correspondig to episode and send to torrent aplication
def download(show,episode)
	for i in 0...episode.length do
		link = "https://thepiratebay.se/search/"+show[:directory]+"+S"+episode[i][:season].to_s.rjust(2,'0')+"E"+episode[i][:episode].to_s.rjust(2,'0')+"+720p"
		open(link) { |io| $html_csv = io.read }
	end
end

######### END FUNCTIONS ##########

############## MAIN ##############

begin
	# Time for benchmark
	beginning = Time.now
	
	# Validate number of args
	if ARGV.length < 2 and ARGV[0] != "-h"
		puts "Invalid number of arguments. See 'series -h'."
		exit 2
	end 

	# Test if short flag is set
	if ARGV[0].downcase =~ /-.x/ 
		$short=1
	else
		$short=0
	end

	#Test if benchmark flag is set
	if ARGV[0].downcase =~ /-.b/ 
		$benchmark=1	
	else
		$benchmark=0
	end

	search_episode=Array.new

	# Tests internet conectivity
	if internet_connection?("http://www.icann.org/") == false
		$offline="No internet connection."
	else
		$offline=""
	end

	case ARGV[0].downcase

	# Returns correctly formated name
	when "-f","-fb"
		for i in 1...ARGV.length do
			name=ARGV[i].scan(/(.*)[sS]\d+/)[0][0]
			show=get_show(name)
			episodes_list=get_episodes(show,"local")

			# Get file extension
			begin
			  	extension = ARGV[1][ARGV[1].rindex('.'),ARGV[1].length]
			  	extension = "".to_s() if ARGV[1].length-ARGV[1].rindex('.') > 5
		 	rescue
		  		extension = "".to_s()
		  	end

		  	# Get file TV show season and episode number
			season=ARGV[1].scan(/[sS]\d+/)[0].scan(/\d+/)
			episode_num=ARGV[1].scan(/[eE]\d+/)[0].scan(/\d+/)

			search_episode<<(episodes_list.find {|episode| episode[:episode] == episode_num[0].to_i and episode[:season] == season[0].to_i})
			if search_episode[0] == nil then
				puts "Episode not found for "+show[:title]+". "+$offline
			else
				puts show[:title]+" - S"+search_episode[:season].to_s.rjust(2,'0')+"E"+search_episode[:episode].to_s.rjust(2,'0')+" - "+search_episode[:title]+extension
			end
		end

	# Next episode
	when "-n","-nx","-nb","-nxb","-nbx"
		for i in 1...ARGV.length do
			show=get_show(ARGV[i].dup)
			episodes_list=get_episodes(show,"local")
			search_episode<<(episodes_list.find {|episode| episode[:special?]=="n" and Date.parse(episode[:airdate]) >= Date.today})
			# If episode not found, forces download mode
			if search_episode[0] == nil then
				episodes_list=get_episodes(show,"download")
				search_episode<<(episodes_list.find {|episode| episode[:special?]=="n" and Date.parse(episode[:airdate]) >= Date.today})
			end
			if search_episode[0] == nil then
				puts "Episode not scheduled for "+show[:title]+". "+$offline
			end
			output(show,search_episode)
			search_episode=Array.new
		end

	# Missing episodes
	when "-m","-mx","-mb","-mxb","-mbx"
		for i in 1...ARGV.length do
			show=get_show(ARGV[i].dup)
			missing_episodes=missing(show)
			if missing_episodes!=nil then
				output(show,missing_episodes)
			end
		end

	# Download missing
	when "-d","-dx","-db","-dxb","-dbx"
		for i in 1...ARGV.length do
			show=get_show(ARGV[i].dup)
			missing_episodes=missing(show)
			if missing_episodes!=nil then
				output(show,missing_episodes)
			end
			download(show,missing_episodes)
		end

	# Last episode
	when "-l","-lx","-lb","-lxb","-lbx"
		
		for i in 1...ARGV.length do
			show=get_show(ARGV[i].dup)
			episodes_list=get_episodes(show,"local")
			search_episode<<(episodes_list.reverse.find {|episode| episode[:special?]=="n" and Date.parse(episode[:airdate]) < Date.today})
			if search_episode[0] == nil then
				episodes_list=get_episodes(show,"download")
				search_episode<<(episodes_list.find {|episode| episode[:special?]=="n" and Date.parse(episode[:airdate]) < Date.today})
			end
			if search_episode[0] == nil then
				puts "Episode not aired for "+show[:title]+". "+$offline
			end
			output(show,search_episode)
			search_episode=Array.new
		end

	# TV show statistics
	when "-s","-sb"
		for i in 1...ARGV.length do
			show=get_show(ARGV[i].dup)
			episodes_list=get_episodes(show,"local")
			puts $offline if $offline != ""
			puts "Name: "+show[:title]
			puts "Network: "+show[:network]
			puts "Country: "+show[:country]
			puts "Seasons: "+episodes_list.last[:season].to_s
			puts "Episodes: "+episodes_list.size.to_s
			puts "First: S"+episodes_list.first[:season].to_s.rjust(2,'0')+"E"+episodes_list.first[:episode].to_s.rjust(2,'0')+" - "+episodes_list.first[:title].to_s+", "+Date.parse(episodes_list.first[:airdate]).to_s
			puts "Last: S"+episodes_list.last[:season].to_s.rjust(2,'0')+"E"+episodes_list.last[:episode].to_s.rjust(2,'0')+" - "+episodes_list.last[:title].to_s+", "+Date.parse(episodes_list.last[:airdate]).to_s
			next_episode=(episodes_list.find {|episode| episode[:special?]=="n" and Date.parse(episode[:airdate]) >= Date.today})
			if next_episode == nil then
				puts "Next: Episode not scheduled for "+show[:title]+"."
			else
				puts "Next: S"+next_episode[:season].to_s.rjust(2,'0')+"E"+next_episode[:episode].to_s.rjust(2,'0')+" - "+next_episode[:title].to_s+", "+Date.parse(next_episode[:airdate]).to_s
			end
		end

	# Show all episodes
	when "-a","-ax","-ab","-axb","-abx"
		for i in 1...ARGV.length do
			show=get_show(ARGV[i].dup)
			episodes_list=get_episodes(show,"local")
			episodes_list.each { |episode| search_episode<<episode }
			output(show,search_episode)
			puts $offline if $offline != ""
		end
	else
		puts "usage: series <option>[x] <tv show name or filename>

options:
	 -f: Returns correctly formated name
	 -n: Next episode
	 -l: Last episode
	 -s: TV show statistics
	 -a: Show all episodes
	 -m: Show missing episode list
	[x]: Short output mode
	[b]: Benchmark mode"

		exit 3
	end

	if $benchmark == 1 then
		puts "Execution time: #{Time.now - beginning} seconds\n"
	end

	exit 0

rescue Interrupt => e
	puts "","Terminated by user."
	puts "Execution time: #{Time.now - beginning} seconds\n"
	exit 1
end
