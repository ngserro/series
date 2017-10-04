#!/usr/bin/ruby -KUW0

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
require 'trollop'

include Amatch

# Load configs
begin
	eval File.open(File.dirname(__FILE__)+'/series.conf').read
rescue
	puts "Configuration file not found."
	exit 1
end

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


# Search parsed "show_list" for tv show with "name"
def get_show_search_list(name,shows_list)

	# Remove all non char from name
	name.gsub!(/\W/,'')
	
	# Fuzzy search. If not found updates file and if still not found, removes "The" from name
	fuzzy_test = JaroWinkler.new(name)
	search_show=(shows_list.detect {|show| fuzzy_test.match(show[:directory].to_s) > 0.94})
	if search_show == nil then
		name=name.downcase.gsub("the","")
		fuzzy_test = JaroWinkler.new(name)
	end
	search_show=(shows_list.detect {|show| fuzzy_test.match(show[:directory].to_s) > 0.94})
	puts "@get_show: search_show: "+search_show.to_s if $opts[:verbose] == true
	
	return search_show
end


# Returns hash with TV show information, exits otherwise
def get_show (name)

	# If file doesnt exist creates header
	if File.exist?($tmp_location+'myshows.txt') != true
		open($tmp_location+'myshows.txt', 'a') { |f|
			f.puts "title,directory,tvrage,tvmaze,start date,end date,number of episodes,run time,network,country"
		}
	end

	# Check myshows
	if File.exist?($tmp_location+'myshows.txt') == true
		# Read file and create array of hashes
		file = File.open($tmp_location+'myshows.txt', :encoding => 'UTF-8')
		shows_list = SmarterCSV.process(file)
		search_show=get_show_search_list(name,shows_list)
		if search_show != nil then
			puts "@get_show: search_show: "+search_show.to_s if $opts[:verbose] == true
			return search_show
		end
	end

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

	search_show=get_show_search_list(name,shows_list)
	if search_show == nil then
		puts "TV Show not found."+$offline
		return nil
	else
		puts "@get_show: search_show: "+search_show.to_s if $opts[:verbose] == true

		open($tmp_location+'myshows.txt', 'a') { |f|
			f.puts "\""+search_show[:title].to_s+"\",\""+search_show[:directory].to_s+"\","+search_show[:tvrage].to_s+","+search_show[:tvmaze].to_s+","+search_show[:start_date].to_s+",\""+search_show[:end_date].to_s+"\",\""+search_show[:number_of_episodes].to_s+"\",\""+search_show[:un_time].to_s+"\",\""+search_show[:network].to_s+"\",\""+search_show[:country].to_s+"\""
		}
		return search_show
	end	
end

# Returns array of hashes with episode information for a given show
def get_episodes(show,mode)

	#link = "http://epguides.com/common/exportToCSV.asp?rage="+show[:tvrage].to_s.chomp
	#filename=$tmp_location+show[:tvrage].to_s+".txt"
	link = "http://epguides.com/common/exportToCSVmaze.asp?maze="+show[:tvmaze].to_s.chomp
	filename=$tmp_location+show[:tvmaze].to_s+".txt"
	
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
	file = File.read(filename)
	# Fixes inexistent airdate field	
	file_fixed = file.gsub(/,\s*,/, ",UNAIRED,")
	File.open(filename, "w") {|file| file.puts file_fixed }
	file = File.open(filename)

	episodes_list = SmarterCSV.process(file)
	
	puts "@get_episodes: episodes_list: "+episodes_list.to_s if $opts[:verbose] == true
	return episodes_list

end

# Returns missing episodes in library
def missing(show)
	# Get last existing and parse information
	cmd = "/bin/ls -1R "+$library_location+" | grep -i \""+show[:title]+" - \" | tail -1"
	#cmd="cat $HOME/Dropbox/log/lista.log | grep -i \""+show[:title]+" - \" | tail -1"
	last_existing = `#{cmd}`

	# Get file TV show season and episode number
	episodes_list=get_episodes(show,"local")
	if last_existing == "" then
		# Last existing not found. All episodes are missing
		search_episode=(episodes_list.select {|episode| !episode[:number].to_s.match(/s/i) and episode[:airdate]!="UNAIRED" and Date.parse(episode[:airdate]) < Date.today  }) 
	else
		season=last_existing.scan(/[sS]\d+/)[0].scan(/\d+/)
		episode_num=last_existing.scan(/[eE]\d+/)[0].scan(/\d+/)
		last_existing_info=(episodes_list.find {|episode| !episode[:number].to_s.match(/s/i) and (episode[:episode] == episode_num[0].to_i and episode[:season] == season[0].to_i)})
		search_episode=(episodes_list.select {|episode| !episode[:number].to_s.match(/s/i) and episode[:airdate]!="UNAIRED" and ( Date.parse(episode[:airdate]) > Date.parse(last_existing_info[:airdate]) and Date.parse(episode[:airdate]) < Date.today)  or (!episode[:number].to_s.match(/s/i)  and episode[:airdate]!="UNAIRED" and Date.parse(episode[:airdate]) >= Date.parse(last_existing_info[:airdate]) and episode[:number]>last_existing_info[:number] and Date.parse(episode[:airdate]) < Date.today) }) 
	end
	puts "@missing: search_episode: "+search_episode.to_s if $opts[:verbose] == true
	return search_episode[0]
end

# Print episode
def output(show,episode)
	# Print output
	for i in 0...episode.length do
		# If airdate is UNAIRED
		episode[i][:airdate] = "01/Jan/1900" if (episode[i][:airdate] == "UNAIRED")

		# If it's a new episode sends notification using boxcar.sh
		if episode[i] != nil and $use_notifications==true and (Date.today-Date.parse(episode[i][:airdate])).to_i.between?(0, 1) then
			cmd="boxcar.sh "+Socket.gethostname+" Series "+"\"Novo Episódio: #{show[:title]} - S#{episode[i][:season].to_s.rjust(2,'0')}E#{episode[i][:episode].to_s.rjust(2,'0')}\""
			`#{cmd}`
		end
		if $opts[:short] == false and episode[i] != nil then
			puts show[:title]+" - S"+episode[i][:season].to_s.rjust(2,'0')+"E"+episode[i][:episode].to_s.rjust(2,'0')+" - "+episode[i][:title]+", "+Date.parse(episode[i][:airdate]).strftime("%A, %d %b %Y").to_s
		elsif episode[i] != nil
			puts show[:title]+" - S"+episode[i][:season].to_s.rjust(2,'0')+"E"+episode[i][:episode].to_s.rjust(2,'0')+", "+Date.parse(episode[i][:airdate]).strftime("%a, %d %b").to_s
		end
	end
end

# Download magnet correspondig to episode and send to torrent aplication
def download(show,episode)
	for i in 0...episode.length do
		magnet=nil
		link = "https://thepiratebay.se/search/"+show[:title]+"+S"+episode[i][:season].to_s.rjust(2,'0')+"E"+episode[i][:episode].to_s.rjust(2,'0')+"+720p+x264"
		cmd="wget --quiet --no-check-certificate "+link+" -O - "
		result = `#{cmd}`
		magnet=result.to_s.match(/magnet:.*?(?=".title)/)
		cmd="/usr/bin/transmission-remote "+$transmission_ip+":"+$transmission_port+" -n "+$transmission_credentials+" -w "+$transmission_dlpath+" -a \""+magnet.to_s+"\""
		p cmd
		result = `#{cmd}`
		puts "Download started for "+link
	end
end

######### END FUNCTIONS ##########

############## MAIN ##############

begin

	$opts = Trollop::options do
		version "test 2.0 (c) 2015 Nuno Serro"
  		banner <<-EOS
Usage:
       series.rb [options] <filename or tv show name>
where [options] are:
EOS
		opt :format, "Returns correctly formated name"
		opt :next, "Next episode"
		opt :last, "Last episode"
		opt :statistics, "TV show statistics"
		opt :showall, "Show all episodes", :short => "a"
		opt :missing, "Show missing episode list"
		opt :download, "Download missing episode list"
		opt :stash, "Stash finished downloads"
		opt :short, "Short output mode", :flag => true, :short => "x"
		opt :benchmark, "Benchmark mode", :flag => true, :short => "b"
		opt :verbose, "Verbose mode", :flag => true, :short => "v"
		conflicts :format, :next, :last, :statistics, :showall, :missing, :download, :stash
	end
	Trollop::die "need at least one option" unless $opts.keys[$opts.length-1].to_s.include? "given"
	Trollop::die "need at least one filename" if ARGV.empty? and $opts[:format]==true
	Trollop::die "need at least one tv show" if ARGV.empty? and ($opts[:missing]==false and $opts[:next]==false and $opts[:download]==false and $opts[:stash]==false)

	#Initializations
	beginning = Time.now
	search_episode=Array.new
	$followed_shows=(($followed_shows.map!{|c| c.downcase.strip}+ARGV.map!{|c| c.downcase.strip}).sort_by{|word| word.downcase}).uniq

	# Tests internet conectivity
	if internet_connection?("http://www.icann.org/") == false
		$offline="No internet connection."
	else
		$offline=""
	end

	# Returns correctly formated name
	if $opts[:format] == true then
		begin
			for i in 0...ARGV.length do
				name=ARGV[i].scan(/(.*)[sS]\d+/)[0][0]
				show=get_show(name)
				episodes_list=get_episodes(show,"local")

				# Get file extension
				begin
				  	extension = ARGV[i][ARGV[i].rindex('.'),ARGV[i].length]
				  	extension = "".to_s() if ARGV[i].length-ARGV[i].rindex('.') > 5
			 	rescue
			  		extension = "".to_s()
			  	end

			  	# Get file TV show season and episode number
				season=ARGV[i].scan(/[sS]\d+/)[0].scan(/\d+/)
				episode_num=ARGV[i].scan(/[eE]\d+/)[0].scan(/\d+/)
				search_episode<<(episodes_list.find {|episode| episode[:episode] == episode_num[0].to_i and episode[:season] == season[0].to_i})

				if search_episode[0] == nil then
					puts "Episode not found for "+show[:title]+". "+$offline
				else
					puts show[:title]+" - S"+search_episode[0][:season].to_s.rjust(2,'0')+"E"+search_episode[0][:episode].to_s.rjust(2,'0')+" - "+search_episode[0][:title]+extension
				end
			end
		rescue
			puts "Invalid filename."
			exit 1
		end
	end

	# Next episode
	if $opts[:next] == true then
		for i in 0...$followed_shows.length do
			show=get_show($followed_shows[i].dup)
			episodes_list=get_episodes(show,"local")
			search_episode[0]=(episodes_list.find {|episode| !episode[:number].to_s.match(/s/i) and episode[:airdate]!="UNAIRED" and Date.parse(episode[:airdate]) >= Date.today})
			# If episode not found, forces download mode
			if search_episode[0] == nil then
				episodes_list=get_episodes(show,"download")
				search_episode[0]=(episodes_list.find {|episode| !episode[:number].to_s.match(/s/i) and episode[:airdate]!="UNAIRED" and Date.parse(episode[:airdate]) >= Date.today})
			end

			if search_episode[0] == nil then
				puts "Episode not scheduled for "+show[:title]+". "+$offline
				next
			end
			output(show,search_episode)
			search_episode=Array.new
		end
	end

	# Missing episodes
	if $opts[:missing]==true then
		for i in 0...$followed_shows.length do
			show=get_show($followed_shows[i].dup)
			missing_episodes=missing(show)
			if missing_episodes!=nil then
				output(show,missing_episodes)
			end
		end
	end

	# Download missing
	if $opts[:download]==true then
		for i in 0...$followed_shows.length do
			show=get_show($followed_shows[i].dup)
			missing_episodes=missing(show)
			if missing_episodes!=[] then
				download(show,missing_episodes)
			else
				puts "No missing episodes of "+show[:title]+" to download."
			end			
		end
	end

	# Last episode
	if $opts[:last]==true then	
		for i in 0...ARGV.length do
			show=get_show(ARGV[i].dup)
			episodes_list=get_episodes(show,"local")
			search_episode<<(episodes_list.reverse.find {|episode| !episode[:number].to_s.match(/s/i) and episode[:airdate]!="UNAIRED" and Date.parse(episode[:airdate]) < Date.today})
			if search_episode[0] == nil then
				episodes_list=get_episodes(show,"download")
				search_episode<<(episodes_list.reverse.find {|episode| !episode[:number].to_s.match(/s/i) and episode[:airdate]!="UNAIRED" and Date.parse(episode[:airdate]) < Date.today})
			end
			if search_episode[0] == nil then
				puts "Episode not aired for "+show[:title]+". "+$offline
			end
			output(show,search_episode)
			search_episode=Array.new
		end
	end

	# TV show statistics
	if $opts[:statistics]==true then
		for i in 0...ARGV.length do
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
			next_episode=(episodes_list.find {|episode| !episode[:number].to_s.match(/s/i) and episode[:airdate]!="UNAIRED" and Date.parse(episode[:airdate]) >= Date.today})
			if next_episode == nil then
				puts "Next: Episode not scheduled for "+show[:title]+"."
			else
				puts "Next: S"+next_episode[:season].to_s.rjust(2,'0')+"E"+next_episode[:episode].to_s.rjust(2,'0')+" - "+next_episode[:title].to_s+", "+Date.parse(next_episode[:airdate]).to_s
			end
		end
	end

	# Show all episodes
	if $opts[:showall]==true then
		for i in 0...ARGV.length do
			show=get_show(ARGV[i].dup)
			episodes_list=get_episodes(show,"local")
			episodes_list.each { |episode| search_episode<<episode }
			output(show,search_episode)
			puts $offline if $offline != ""
		end
	end
	
	# Stash finished downloads
	if $opts[:stash]==true then
		
	end
	
	if $opts[:benchmark] == true then
		puts "Execution time: #{Time.now - beginning} seconds\n"
	end

	exit 0

rescue Interrupt => e
	puts "","Terminated by user."
	puts "Execution time: #{Time.now - beginning} seconds\n"
	exit 1
end
