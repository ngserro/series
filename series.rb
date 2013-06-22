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
require 'etc'

$cache_permite=1 	# 1 - Permite criacao de ficheiro local de cache, 0 - Nao permite
$benchmark=0 		# 1 - Mostra o tempo de execucao, 0 - Nao mostra

$cache_folder_name=Dir.pwd+"/series_cache"
$index_file_name=Dir.pwd+"/series_index.txt"

##############################
# Variaveis Globais
##############################

# Variaveis globais usadas como contadores para estatisticas
$total_temp=0
$total_epis=0
$estatisticas=0

$total_epis_offline=0
$total_epis_online=0

# Variavel global para flag de versao curta
$short=0

# Variavel global para flag de acesso a cache de series
$cache=0

# Variavel global para flag de episodio com nome TBA
$tba=0

# Variavel global para flag de listagem
$listagem=0

##############################
# AUXILIARES
##############################

# Cria directorio se nao existir
def create_if_missing *names
	names.each do |name| Dir.mkdir(name) unless File.directory?(name)
	end
end 

# Testa se tem ligacao a Internet
def testa_ligacao(addr)
	begin
		open(addr)
		return 1
	rescue
		return 0  
	end
end

# testa link
def isLive?(url)
	uri = URI.parse(url)
	response = nil
	Net::HTTP.start(uri.host, uri.port) { |http|
		response = http.head(uri.path.size > 0 ? uri.path : "/")
	}  
	return response.code == "200"
end

##############################
# Classe ListaEpisodio.
##############################
# Contem metodos "formata_nome", "cria_lista", "procura_episodio", "procura_proximo" e "procura_ultimo".

class ListaEpisodios

  	# Metodo para criar um nome correctamente formatado.
	def self.formata_nome(nome)
		begin
  			nome["temporada"] = "0" + nome["temporada"] if Integer(nome["temporada"]) < 10  and nome["temporada"].length < 2
  			nome["num_epis"] = "0" + nome["num_epis"] if Integer(nome["num_epis"]) < 10 and nome["num_epis"].length < 2
  		rescue
  		end
  		if $short == 0 then
  			(nome["serie"] + " - S" + nome["temporada"].to_s + "E" + nome["num_epis"].to_s + " - " + nome["nome_epis"].chomp).sub(/\s$/,'')
		else   # Formata nome no modo "short"
			data=Date.parse(nome["data"],comp=true)
			nome["data"] = data.strftime("%a, %d %b")
			(nome["serie"] + " - S" + nome["temporada"] + "E" + nome["num_epis"])
		end
	end

  	# Metodo para ler todos os episodios correspondentes a serie da pagina "link" ou da cache, se existir, e coloca-los na variavél lista.
	def self.cria_lista (nome_serie, link)
  		episodio = 0
  		temporada = 0
  		lista=[]
		# Modo offline. Tenta criar lista a partir da cache.
		if $cache == 0 and $cache_permite == 1 then
			$cache=1
			begin
				create_if_missing $cache_folder_name
				file = File.new($cache_folder_name+"/"+nome_serie+".txt", "r")
				while (linha = file.gets)
					linha_anterior=linha
					fim_nome=linha.index(' - ')
					fim_episodio=linha.index('||')
					$total_epis +=1
					lista.push("serie"=>linha[0,fim_nome].to_s,"temporada"=>linha[fim_nome+4,2].to_s,"num_epis"=>linha[linha.index(/E\d\d/)+1,2].to_s,"nome_epis"=>linha[linha.rindex(' - ')+3,fim_episodio-(linha.rindex(' - ')+3)].to_s,"data"=>linha[fim_episodio+3,linha.length-(fim_episodio+3)].to_s)
				end
				$total_temp=Integer(linha_anterior[fim_nome+4,2].to_s)
				file.close
				$total_epis_offline=$total_epis
				return lista
			rescue
			# Nao encontrou ficheiro de cache, continua a execucao lendo a pagina "link"
			end
		end

		# Modo online. Nao existe cache. Procura online.
		$total_epis=0
		lista=[]           
		begin
			# Abre pagina referenciada por "link".
	  		open(link) do |f|
	  			f.each do |linha|
		  			# Achou uma mudanca de temporada, incrementa "temporada" e coloca "episodio" a zero.
		  			if linha["Season "+(temporada+1).to_s] then
		  				temporada +=1
		  				episodio = 0
		  				$total_temp +=1
		  			end
		  			if linha[temporada.to_s+"-"] then
		  				if Integer(temporada)<10 then
		  					episodio = linha[linha.index(temporada.to_s+"-")+2,2]
		  				else
		  					episodio = linha[linha.index(temporada.to_s+"-")+3,2]
		  				end
		  				linha_back=linha.dup
						# Achou  uma "temporada". Filtra todo o lixo.
						if linha.index("'>")!=nil then
							if linha.index("Trailer")!=nil or linha.index("Recap")!=nil then
								linha = linha.sub!(/<.*?'>/, "") if linha!=nil
								linha = linha.sub!(/<\/a.*$/, "") if linha!=nil
							else	       
								linha = linha.sub!(/<.*'>/, "") if linha!=nil
							end
						else
							linha = linha.sub!(/<.*">/, "") if linha!=nil
						end
						# Procura data nesta "linha".
						begin
							data=Date.parse(linha,comp=true) if linha!=nil
			  				# Se a data for maior do que a anterior em 1000 dias corrige o erro por colocando-a igual a anterior. Isto introduz erro.
							if $total_epis > 1 then
								teste = lista[$total_epis-1]
								if episodio.to_i == 1 then 
							  		data=Date.parse(linha,comp=true) 
							  	else
							  		data=Date.parse(teste["data"],comp=true) if (Date.parse(linha,comp=true) - Date.parse(teste["data"],comp=true)).to_i > 300 and Date.parse(teste["data"],comp=true)!=Date.parse("01 Jan 1900",comp=true)
							  	end
							end
							if linha.index("UNAIRED")!=nil then
								data=Date.parse("01 Jan 1900",comp=true)
							end
						rescue
							#Nao acho data nesta linha, coloca da
			  				data=Date.parse("01 Jan 1900",comp=true)
						end
						linha = linha.sub!(/.*  /, "") if linha!=nil
						if linha!=nil then
							if linha.index("</a>")!=nil then
								linha = linha.sub!("</a>", "") if linha!=nil
							end
							$total_epis +=1
							$total_epis_online=$total_epis
							temporadaf = temporada
							temporadaf = "0" + temporada.to_s if Integer(temporada) < 10 and temporada.to_s.length < 2
							lista.push("serie"=>nome_serie.to_s,"temporada"=>temporadaf.to_s,"num_epis"=>episodio.to_s,"nome_epis"=>linha.chomp,"data"=>data.strftime("%A, %d %b %Y"))
						  	#puts nome_serie.to_s+temporada.to_s+episodio.to_s+linha.chomp+data.strftime("%A, %d %b %Y")
						end
					end
				end
			end
		rescue StandardError
			puts "ERRO: Falha a processar link " + link +" !"
			exit(2)
		end

		# Corrige qualquer erro que possa existir com datas onde o parse falhou. Por exemplo o episodio 2 foi em 2010 mas o 3 em 1999. Corre duas vezes.
		for i in 1..2 do
			data_anterior = Date.parse("01 Jan 1800",comp=true).strftime("%A, %d %b %Y")
			conta_posicao=0
			lista.each do |episodio|
				if (Date.parse(episodio["data"],comp=true) - Date.parse(data_anterior,comp=true)).to_i < 0 and episodio["data"] != Date.parse("01 Jan 1900",comp=true).strftime("%A, %d %b %Y") then 
					lista[conta_posicao-1]["data"]=episodio["data"]
				end
				data_anterior = episodio["data"]
				conta_posicao+=1
			end
		end

		# Actualiza cache com o que foi lido da pagina "link" caso existam novos episodios
		if $cache_permite ==1  and $total_epis_online > $total_epis_offline or $tba == 1 then
			short_save=$short # Guarda estado da flag short
	  		$short=0
	  		begin
	  			file = File.new($cache_folder_name+"/"+nome_serie+".txt", "w")
	  			lista.each do |episodio|
	  				file.puts  ListaEpisodios.formata_nome(episodio)+" || "+episodio["data"] if (formata_nome(episodio)!=nil)
	  			end
	  			file.close
			end
			$short=short_save
		end
		return lista
	end

	# Metodo para procurar episodio pedido, retornando o nome do ficheiro correctamente formatado.
	def self.procura_episodio (temporada, num_epis,lista)
	  	procura = nil
	  	lista.each do |episodio|
	  		procura=episodio if episodio["temporada"] == temporada and episodio["num_epis"] == num_epis
	  	end
		# Se achou episodio chama "formata_nome" para o episodio encontrado,
		# caso contrario sai com erro.
		if procura != nil and procura["nome_epis"].index('TBA') == nil then
			ListaEpisodios.formata_nome(procura)
		else
			if procura != nil and $tba == 1 then
				return ListaEpisodios.formata_nome(procura)
			end
			$tba=1 if procura != nil and procura["nome_epis"].index('TBA') != nil
			return 1
		end
	end

	# Metodo para procurar e retornar proximo episodio a ser exibido.
	def self.procura_proximo (nome_serie,lista)
	  	episodio = nil
	  	procura = nil
	  	data_actual = Date.today.strftime("%A, %d %b %y")
	  	lista.each do |episodio|
	  		if Date.parse(episodio["data"],comp=true) >= Date.parse(data_actual.to_s,comp=true) then
	  			procura=episodio
				break #Faz break porque assumo que a lista esta ordenada, assim o primeiro que acha depois da data actual => proximo
			end
		end
		# Se achou episodio chama "formata_nome" para o episodio encontrado,
		# caso contrario sai com erro.
		if procura != nil then
			ListaEpisodios.formata_nome(procura)+ ", " + procura["data"]
		else
			return 1
		end
	end

	# Metodo para procurar e retornar ultimo episodio exibido.
	def self.procura_ultimo (nome_serie,lista)
  		episodio = nil
  		procura = nil
	  	data_actual = Date.today.strftime("%A, %d %b %y")    
	  	dif_datas=10000
		# Procura episodio mais proximo da "data_actual".
		lista.each do |episodio|
			puts ListaEpisodios.formata_nome(episodio)+ ", " + episodio["data"] if $listagem==1
			dif = (Date.parse(data_actual.to_s,comp=true) - Date.parse(episodio["data"],comp=true)).to_i
			if  dif < dif_datas and dif > 0  then
				dif_datas = (Date.parse(data_actual.to_s,comp=true) - Date.parse(episodio["data"],comp=true)).to_i
				procura=episodio
			end
		end
		# Achou a diferenca de datas minima (episodio mais recente), chama "formata_nome" 
		# para o episodio encontrado, caso contrario sai com erro.
		if procura != nil then
			ListaEpisodios.formata_nome(procura)+ ", " + procura["data"]
		else
			return 1
		end
	end
end

##########################################################
# Classe Serie composta por "keywords", "nome" e "link".
##########################################################
# Contem metodos "initialize", "procura_serie", "limpa" e "capitaliza".

class Serie
	attr_accessor :keywords, :nome, :link

	def initialize (keywords, nome, link)
		@keywords=keywords
		@nome=nome
		@link=link
	end

  	# Metodo para comparar nome do ficheiro passado como argumento
  	# com palavras chave lidas de $index_file_name.

 	def self.procura_serie(nome_ficheiro)
  		procura = nil
  		ObjectSpace.each_object(Serie)  { |o|
  			procura = o
  			procura.keywords.each { |keyword|
				# Achou a serie na base de dados. Retorna nome correcto
				# e link correspndente a serie.
				return procura.nome, procura.link if nome_ficheiro[keyword] != nil
			}	
		}
		# Se chegou aqui nao encontrou serie na base de dados.
		# Vai comecar a inventar....
		flag =0
		# Se o primeiro caracter for um numero, salta o passo seguinte
		if nome_ficheiro.scan(/^\d+/)[0] !=nil then
			if nome_ficheiro[0].ord >= 48 and nome_ficheiro[0].ord <= 57 then
				flag=1
				nome_serie=nome_ficheiro.to_s
			else
				lixo, temporada = nome_ficheiro.scan(/\d+/).map { |n| n.to_i }
			end    
		else
			temporada = nome_ficheiro.scan(/\d+/)[0]
			if temporada == nil then
				nome_serie = nome_ficheiro
				flag = 1
			end
		end
		
		nome_serie = nome_ficheiro[0,nome_ficheiro.index(temporada.to_s)] if flag == 0
		nome_serie = nome_serie.gsub(/^the/,"The")    
		# "nome_serie" ficou com a parte do nome do ficheiro de entrada ate ao primeiro digito.
		# nome_da_serie.s01e32.asdkjshdk.avi -> .s fica no nome da serie. proximo comando limpa isto
		if nome_serie.rindex('.') != nil then
			nome_serie = nome_serie[0,nome_serie.rindex('.')]
		end
		#se achar " - s" remove
		if nome_serie.rindex(' - s') != nil then
			nome_serie = nome_serie[0,nome_serie.rindex(' - s')]
		end
		link = "http://epguides.com/"+Serie.limpa(nome_serie,"link")+"/".chomp
		#Caso o link esteja morto, experimenta retirando o último caracter
		if isLive?(link) == false then
			link.sub!(/.\/$/,'/')
			nome_serie.sub!(/.$/,'')
		end
		# Testa se tem ligacao a Internet
		if testa_ligacao "http://epguides.com/" == 0
			return Serie.limpa(Serie.capitaliza(nome_serie),"offline"), link
		end
		begin
		  # Vai ver se o link e valido se se consegui ligar anteriormente, se for tenta tirar nome correcto da serie
		  open(link) do |f|
		  	f.each do |linha|
		  		if linha["<title>"] then
				# Achou  linha com nome de serie. Filtra todo o lixo.
				nome_serie=linha[linha.index(">")+1,linha.index("(a")-8]
					break
				end
			end
		end
		rescue
			puts "ERRO: Serie nao encontrada!"
			exit(1)
		end
		return Serie.capitaliza(nome_serie), link
	end

  	# Metodo para limpar string the caracteres indezejados no link.
  	def self.limpa(string,modo)
	  	limpo=string.gsub(".","")
	  	limpo=limpo.gsub(":","")
	  	limpo=limpo.gsub("[","")
	  	limpo=limpo.gsub("]","")
	  	limpo=limpo.gsub("-","")
	  	limpo=limpo.gsub("_"," ") if modo=="offline"
	  	limpo=limpo.gsub("_","") if modo=="link"
	  	limpo=limpo.gsub(" ","") if modo=="link"
	  	limpo=limpo.gsub(",","")
	  	limpo=limpo.gsub(/^the/,"") if modo=="link"
	  	limpo=limpo.gsub(/^The/,"") if modo=="link"
	  	limpo=limpo.gsub("&","and")
	  	return limpo
 	end

  	# Capitaliza o nome da serie
  	def self.capitaliza(string)
  		teste=string.split(' ')
  		aux=""	
  		teste.each do |palavra|
  			aux=aux+palavra.capitalize+" "
  		end
  		aux[aux.length-1]=""
		return aux
	end
end


####################################
# INICIO
####################################
begin
	beginning = Time.now
	# Abre o ficheiro $index_file_name e le as palavras chave, nome de serie e link correspondente.
	begin
		file = File.new($index_file_name, "r")
		while (linha = file.gets)
			primeiro_break=linha.index(';')
			segundo_break=linha.index(';',primeiro_break+1)
			Serie.new(linha[0,primeiro_break].split(','),linha[primeiro_break+1,segundo_break-primeiro_break-1],linha[segundo_break+1,linha.length])
		end
		file.close
	rescue
 	# Ficheiro index nao existe ou houve erro na abertura.
	end

	# Junta todos os argumentos depois do 1o, num so argumento.
	if ARGV.length > 2 then
		entrada=""
		for i in 1..(ARGV.length-1) do
			entrada << ARGV[i]
		end
		ARGV[1] = entrada
	end

	# Se existir argumento de entrada "-p" executa procura de proximo episodio.
	if ARGV[0] == "-p" or ARGV[0] == "-ps" and ARGV[1] !=nil then
		if ARGV[0] == "-ps" then
			$short=1
		end
		nome_e_link = Serie.procura_serie(ARGV[1].gsub('.','_').to_s().downcase)
		nome_e_link[0]= Serie.capitaliza(nome_e_link[0])
		lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
		proximo=ListaEpisodios.procura_proximo(nome_e_link[0],lista)
		if proximo == 1 and $cache ==1 then
			lista=nil
			lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
			proximo=ListaEpisodios.procura_proximo(nome_e_link[0],lista)
		end
		if proximo == 1 then
			puts "ERRO: Nao existem episodios da serie \"" + nome_e_link[0] + "\" agendados!"
			puts "Tempo decorrido: #{Time.now - beginning} segundos\n" if $benchmark==1
			exit(1)
		else
			puts proximo
			puts "Tempo decorrido: #{Time.now - beginning} segundos\n" if $benchmark==1
			exit(0)
		end
	elsif ARGV[0] == "-p" or ARGV[0] == "-ps" and ARGV[1] ==nil
		puts "ERRO: Falta nome da serie como argumento!"
		exit(3)
	end

	# Se existir argumento de entrada "-u" executa procura de ultimo episodio.
	if ARGV[0] == "-u" or ARGV[0] == "-us"  and ARGV[1] !=nil then
		if ARGV[0] == "-us" then
			$short=1
		end
		nome_e_link = Serie.procura_serie(ARGV[1].gsub('.','_').to_s().downcase)
		nome_e_link[0]= Serie.capitaliza(nome_e_link[0])
		lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
		ultimo=ListaEpisodios.procura_ultimo(nome_e_link[0],lista)
		if ultimo == 1 and $cache ==1 then
			lista=nil
			lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
			ultimo=ListaEpisodios.procura_ultimo(nome_e_link[0],lista)
		end
		if ultimo == 1 then
			puts "ERRO: Ultimo episodio da serie \"" + nome_e_link[0] + "\" nao encontrado!"
			puts "Tempo decorrido: #{Time.now - beginning} segundos\n" if $benchmark==1
			exit(1)
		else
			puts ultimo
			puts "Tempo decorrido: #{Time.now - beginning} segundos\n" if $benchmark==1
			exit(0)
		end  
	elsif ARGV[0] == "-u" and ARGV[1] ==nil
		puts "ERRO: Falta nome da serie como argumento!"
		exit(3)
	end

    # Se existir argumento de entrada "-l" lista episodios da serie.
	if ARGV[0] == "-l" or ARGV[0] == "-ls" and ARGV[1] !=nil then
		if ARGV[0] == "-ls" then
			$short=1
		end
		$listagem=1
		nome_e_link = Serie.procura_serie(ARGV[1].gsub('.','_').to_s().downcase)
		nome_e_link[0]= Serie.capitaliza(nome_e_link[0])
		lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
		ultimo=ListaEpisodios.procura_ultimo(nome_e_link[0],lista)
		exit(0)
	elsif ARGV[0] == "-l" or ARGV[0] == "-ls" and ARGV[1] ==nil
		puts "ERRO: Falta nome da serie como argumento!"
		exit(3)
	end


	# Se existir argumento de enstrada "-e" mostra estatisticas da serie.
	if ARGV[0] == "-e" or ARGV[0] == "-es" and ARGV[1] !=nil then
		nome_e_link = Serie.procura_serie(ARGV[1].gsub('.','_').to_s().downcase)
		$cache=1
		# Testa se tem ligacao a Internet
		$cache = 0 if testa_ligacao "http://epguides.com/" == 0
		lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
		$estatisticas=1
		nome_e_link[0]= Serie.capitaliza(nome_e_link[0])
		puts "Nome: "+nome_e_link[0]
		puts "Numero de Temporadas: "+$total_temp.to_s
		puts "Total de Episodios: "+$total_epis.to_s
		puts "Primeiro: "+ListaEpisodios.formata_nome(lista[0])+", " + lista[0]["data"] if lista[0] != nil
		if ultimo=ListaEpisodios.procura_ultimo(nome_e_link[0],lista) == 1 then
			puts "Ultimo: Ultimo episodio da serie \"" + nome_e_link[0] + "\" nao encontrado!"
		else
		 	puts "Ultimo: "+ListaEpisodios.procura_ultimo(nome_e_link[0],lista).gsub("ERRO: ","")
		end
		if proximo=ListaEpisodios.procura_proximo(nome_e_link[0],lista) ==1 then
			puts "Proximo: Nao existem episodios da serie \"" + nome_e_link[0] + "\" agendados!"
		else
		  	puts "Proximo: "+ListaEpisodios.procura_proximo(nome_e_link[0],lista).gsub("ERRO: ","")
		end
		puts "Tempo decorrido: #{Time.now - beginning} segundos\n"
		exit(0)
	elsif ARGV[0] == "-e" and ARGV[1] ==nil
		puts "ERRO: Falta nome da serie como argumento!"
		exit(3)
	end

	# Se nao existir argumento de entrada "-X" executa procura de episodio correspondente ao argumento de entrada.
	if ARGV[0] != "-p" and ARGV[0] != "-ps" and ARGV[0] != "-u" and ARGV[0] != "-us" and ARGV[0] != "-e" and ARGV[0] != "-l" and ARGV[0] != "-ls" and ARGV.length > 0 then
		if ARGV[0] == "-s" then
			ARGt = ARGV[1].to_s
			$short=1
		else  
			ARGt = ARGV[0].to_s
		end
	  	# Le a extensao, temporada e numero de episodio do argumento de entrada.
	  	begin
		  	extensao = ARGt[ARGt.rindex('.'),ARGt.length]
		  	extensao = "".to_s() if ARGt.length-ARGt.rindex('.') > 5
	 	rescue
	  		extensao = "".to_s()
	  	end
	  	#Remove pontos (pelo sim, pelo nao)
	  	ARG=ARGt.gsub(".","_")
	  	# Utilizando o argumento de entrada, chama Serie.procura_serie, para obter
		# nome e link correcto da serie, com base no ficheiro $index_file_name.
		nome_e_link = Serie.procura_serie(ARG.to_s().downcase)
		#temporada, num_epis = ARG.scan(/\d+/).map { |n| n.to_i }
		scan = ARG.scan(/[sS]\d+/)
		temporada=scan[0].sub(/[sS]/,"")
		scan = ARG.scan(/[eE]\d+/)
		num_epis=scan[0].sub(/[eE]/,"")
		if temporada == nil or num_epis ==nil then
			if temporada > 99 then # Se tiver mais que 3 digitos, assume 1o como serie e restantes como episodio
				temporada=temporada.to_s
				num_epis=temporada[1,2]
				temporada=temporada[0,1]
			else  
				puts "ERRO: Informacao de temporada ou numero de episodio inexistente!"
				exit(1)
			end
		end
	  	# Coloca a segunda parte do nome da serie em maiusculas, caso exista.
		# Se o nome da serie for do tipo The nome, capitaliza nome. Só se não tiver sido usado o index.
		nome_e_link[0]= Serie.capitaliza(nome_e_link[0])
		# Le informacao do site para uma dada serie.
		lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
		# Dados da serie lidos. Procura temporada e episodio pedidos.
		temporada=temporada.to_s
		num_epis=num_epis.to_s
		temporada = "0" + temporada if temporada[0]!=48 and temporada.to_i < 10  and temporada.length < 2
		num_epis = "0" + num_epis if num_epis.to_i < 10 and num_epis.length < 2
		busca=ListaEpisodios.procura_episodio(temporada.to_s(),num_epis.to_s(),lista)
		if busca == 1 and $cache ==1 then
		  	# Se está aqui não encontrou na primeira procura
		  	lista=[]
		  	lista=ListaEpisodios.cria_lista(nome_e_link[0], nome_e_link[1].chomp)
		  	busca=ListaEpisodios.procura_episodio(temporada.to_s(),num_epis.to_s(),lista)
		end
		if busca == 1 then
		  	puts "ERRO: Episodio nao encontrado!"
		  	puts "Tempo decorrido: #{Time.now - beginning} segundos\n" if $benchmark==1
		  	exit(1)
		else
		  	puts busca.to_s+extensao
		  	puts "Tempo decorrido: #{Time.now - beginning} segundos\n" if $benchmark==1
		  	exit(0)
		end
	else
		puts "Sintaxe: series.rb [OPCAO] <nome da serie ou ficheiro>

Opcoes:
  : Retorna nome do ficheiro correctamente formatado
-p: Proximo Episodio
-u: Ultimo Episodio
-e: Estatisticas da Serie
-l: Lista episodios
-s: Retorna nome do ficheiro formatado em versao curta
Xs: Versao curta"
		exit(3)
	end
rescue Interrupt => e
	puts "\nTempo decorrido: #{Time.now - beginning} segundos\n"
	exit(1)
end
