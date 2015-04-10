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

require 'smarter_csv'
require 'amatch'
require 'slop'

include Amatch

############ SETTINGS ############

$benchmark=1		# Toggle execution time display
$temp_file="/tmp/"	# Temporary file location

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

# Cria directorio se nao existir
def create_if_missing *names
	names.each do |name| Dir.mkdir(name) unless File.directory?(name)
	end
end 


# Returns hash with TV show information, exits otherwise
def get_show (name)

	# Remove all non char from name
	name.gsub!(/\W/,'')

	# Index file doesnt exist and we are offline :(
	if File.exist?($temp_file+'allshows.txt') == false and $offline=="No internet connection."
		puts "No index file and no internet connection."
		exit 4
	end

	# Index file doesnt exist, but we are online. Download to file and parse
	if File.exist?($temp_file+'allshows.txt') == false and $offline!="No internet connection."
		open("http://epguides.com/common/allshows.txt") { |io| $html_csv = io.read }
		File.open($temp_file+'allshows.txt', 'w') {|f| f.write($html_csv) }
	end

	# Read file and create array of hashes
	file = File.open($temp_file+'allshows.txt', :encoding => 'Windows-1252')
	shows_list = SmarterCSV.process(file)

	# Fuzzy search. If not found updates file and if still not found, removes "The" from name
	fuzzy_test = JaroWinkler.new(name)
	search_show=(shows_list.detect {|show| fuzzy_test.match(show[:directory].to_s) > 0.9})
	if search_show == nil then
		name=name.downcase.gsub("the","")
		fuzzy_test = JaroWinkler.new(name)
	end
	search_show=(shows_list.detect {|show| fuzzy_test.match(show[:directory].to_s) > 0.9})

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
	filename=$temp_file+show[:tvrage].to_s+".txt"

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

def output(show,episode)
	# Print output, only for -n and -l options
	if $short == 0 then
		puts show[:title]+" - S"+episode[:season].to_s.rjust(2,'0')+"E"+episode[:episode].to_s.rjust(2,'0')+" - "+episode[:title]+", "+Date.parse(episode[:airdate]).strftime("%A, %d %b %Y").to_s
	else
		puts show[:title]+" - S"+episode[:season].to_s.rjust(2,'0')+"E"+episode[:episode].to_s.rjust(2,'0')+", "+Date.parse(episode[:airdate]).strftime("%a, %d %b").to_s
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

	# Merges remaining arguments
	if ARGV.length >= 2 then
		aux=""
		for i in 1..(ARGV.length-1) do
			aux << ARGV[i]
		end
		ARGV[1] = aux
	end

	# Tests internet conectivity
	if internet_connection?("http://www.icann.org/") == false
		$offline="No internet connection."
	else
		$offline=""
	end

	case ARGV[0].downcase

	# Returns correctly formated name
	when "-f"

		name=ARGV[1].scan(/(.*)[sS]\d+/)[0][0]
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

		search_episode=(episodes_list.find {|episode| episode[:episode] == episode_num[0].to_i and episode[:season] == season[0].to_i})
		if search_episode == nil then
			puts "Episode not found. "+$offline
			exit 7
		else
			puts show[:title]+" - S"+search_episode[:season].to_s.rjust(2,'0')+"E"+search_episode[:episode].to_s.rjust(2,'0')+" - "+search_episode[:title]+extension
		end

	# Next episode
	when "-n","-nx"
		
		show=get_show(ARGV[1])
		episodes_list=get_episodes(show,"local")
		search_episode=(episodes_list.find {|episode| Date.parse(episode[:airdate]) > Date.today})
		# If episode not found, forces download mode
		if search_episode == nil then
			episodes_list=get_episodes(show,"download")
			search_episode=(episodes_list.find {|episode| Date.parse(episode[:airdate]) > Date.today})
		end
		if search_episode == nil then
			puts "Episode not scheduled. "+$offline
			exit 8
		end
		output(show,search_episode)

	# Last episode
	when "-l","-lx"
		
		show=get_show(ARGV[1])
		episodes_list=get_episodes(show,"local")
		search_episode=(episodes_list.reverse.find {|episode| Date.parse(episode[:airdate]) < Date.today})
		# If episode not found, forces download mode
		if search_episode == nil then
			episodes_list=get_episodes(show,"download")
			search_episode=(episodes_list.find {|episode| Date.parse(episode[:airdate]) < Date.today})
		end
		if search_episode == nil then
			puts "Episode not scheduled. "+$offline
			exit 8
		end
		output(show,search_episode)

	# TV show statistics
	when "-s"

		show=get_show(ARGV[1])
		episodes_list=get_episodes(show,"local")
		puts $offline if $offline != ""
		puts "Name: "+show[:title]
		puts "Network: "+show[:network]
		puts "Country: "+show[:country]
		puts "Seasons: "+episodes_list.last[:season].to_s
		puts "Episodes: "+episodes_list.last[:number].to_s
		puts "First: S"+episodes_list.first[:season].to_s.rjust(2,'0')+"E"+episodes_list.first[:episode].to_s.rjust(2,'0')+" - "+episodes_list.first[:title].to_s+", "+Date.parse(episodes_list.first[:airdate]).to_s
		puts "Last: S"+episodes_list.last[:season].to_s.rjust(2,'0')+"E"+episodes_list.last[:episode].to_s.rjust(2,'0')+" - "+episodes_list.last[:title].to_s+", "+Date.parse(episodes_list.last[:airdate]).to_s
		next_episode=(episodes_list.find {|episode| Date.parse(episode[:airdate]) > Date.today})
		if next_episode == nil then
			puts "Next: Episode not scheduled."
		else
			puts "Next: S"+next_episode[:season].to_s.rjust(2,'0')+"E"+next_episode[:episode].to_s.rjust(2,'0')+" - "+next_episode[:title].to_s+", "+Date.parse(next_episode[:airdate]).to_s
		end

	# Show all episodes
	when "-a","-ax"
		show=get_show(ARGV[1])
		episodes_list=get_episodes(show,"local")
		episodes_list.each { |episode| output(show,episode) }
		puts $offline if $offline != ""
	else
		puts "usage: series <option>[x] <tv show name or filename>

options:
	 -f: Returns correctly formated name
	 -n: Next episode
	 -l: Last episode
	 -s: TV show statistics
	 -a: Show all episodes
	[x]: Short output"
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
