from tld import get_tld

BITEXTOR=config["bitextor"]

LANG1=config["lang1"]
LANG2=config["lang2"]
MODEL='share/bitextor/model/keras.model'
WEIGHTS='share/bitextor/model/keras.weights'
TMPDIR=config["temp"]
MINQUALITY=config["minquality"]
MAXLINES=config["maxlines"]

#Working paths
permanent=config["permanent"]
intermediate=config["intermediate"]

#Dictionary
if "dic" in config:
  DIC=config["dic"]
else:
  DIC=None

#Option to use the NLTK tokenizer
if "nltk" in config and (config["nltk"]==True):
  USENLTK='--nltk'
else:
  USENLTK=''

#Option to ignore Boilerpipie: if the option is enabled, boilerpipe is not used
if "ignore-boilerpipe-cleaning" in config and config["ignore-boilerpipe-cleaning"]==True:
  IGNOREBOILER="1"
else:
  IGNOREBOILER="0"

#Option to use the JHU-pipeline pre-processing tool; it can be only used with HTTrack
if "jhu-lett" in config and config["jhu-lett"]==True:
  LETT="jlett"
else:
  LETT="lett"

#Option to use HTTrack for crawling instead of the native bitextor crawler
if "httrack" in config and config["httrack"]==True:
  CRAWLTARGET="httrack"
else:
  CRAWLTARGET="creepy"

############ OPTIONS FOR THE NATIVE BITEXTOR CRAWLER ############

#If this option is enabled the crawler will keep crawling across a whole top-level domain (.es, .com, .fr, etc.)
if "crawl-tld" in config and config["crawl-tld"]==True:
  TLD_CRAWL="-D"
else:
  TLD_CRAWL=""

#If this option is enabled, a size-limit is set for crawled data (for example "size-limit": "1G")
if "size-limit" in config:
  CRAWLSIZELIMIT="-s "+config["size-limit"]
else:
  CRAWLSIZELIMIT=""

#If this option is enabled, a time-limit is set for crawling data (for example "time-limit": "1h")
if "time-limit" in config:
  CRAWLTIMELIMIT="-t "+config["time-limit"]
else:
  CRAWLTIMELIMIT=""

#Option to set how many threads will be used for crawling (default value: 2). Note that too many threads can cause the server hosting the website to reject some of the simultaneous connections.
if "crawler-num-threads" in config:
  CRAWLJOBS="-j "+str(config["crawler-num-threads"])
else:
  CRAWLJOBS="-j 2"

#Connection timeout in the crawler
if "timeout-crawl" in config:
  CRAWLTIMEOUT="-o "+config["timeout-crawl"]
else:
  CRAWLTIMEOUT=""

#If this option is set, the "crawler" object will be dump as a pickle, so crawling can be continued afterwards
if "write-crawling-file" in config:
  CRAWLDUMPARGS="-d "+config["write-crawling-file"]
else:
  CRAWLDUMPARGS=""

#If this option is set, crawling will be continued from the pickle object dumped in a previous crawl
if "continue-crawling-file" in config:
  CONTINUECRAWL="-l "+config["continue-crawling-file"]
else:
  CONTINUECRAWL=""


############ OPTIONS FOR THE MALIGN ALIGNER ############

if "paracrawl-aligner-command" in config:
  MT_COMMAND=config["paracrawl-aligner-command"]
  DOCALIGNEXT="paracrawl"
else:
  MT_COMMAND=""
  DOCALIGNEXT="bitextor"

############ FILTERING AND POST-PROCESSING OPTIONS ############

if "bicleaner" in config:
  BICLEANEROPTION=",bicleaner"
  BICLEANER="bicleaner"
  BICLEANER_CONFIG=config["bicleaner"]
else:
  BICLEANEROPTION=""
  BICLEANER="segclean"

if "bicleaner-threshold" in config:
  BICLEANER_THRESHOLD=config["bicleaner-threshold"]
else:
  BICLEANER_THRESHOLD=0.0

if "elrc" in config and config["elrc"]==True:
  ELRCSCORES="elrc"
else:
  ELRCSCORES=BICLEANER

#========================= MAPPING URLS AND OUTPUT FILES =========================#

def getSubDomainsFromURLs():
	subdomains={}
	for url in config["urls"]:
		proc_url=get_tld(url, as_object=True)
		if proc_url.subdomain == "":
			subdomain=proc_url.fld
		else:
			subdomain=proc_url.subdomain+"."+proc_url.fld
		subdomains[subdomain]=url
	return subdomains

def getDomainsFromURLs():
	domains={}
	for url in config["urls"]:
		proc_url=get_tld(url, as_object=True)
		domain=proc_url.domain
		if domain not in domains:
			domains[proc_url.fld]=[]
		if proc_url.subdomain == "":
			subdomain=proc_url.fld
		else:
			subdomain=proc_url.subdomain+"."+proc_url.fld
		domains[proc_url.fld].append(subdomain)
	return domains

subdomain_url_map=getSubDomainsFromURLs()
domain_subdomain_map=getDomainsFromURLs()

#================================== TARGET FILES ==================================#
rule all:
	input:
		expand("{dir}/{l1}-{l2}.tmx", dir=permanent, l1=LANG1, l2=LANG2)

#================================== PREPROCESSING ==================================#
#"http://www.elenacaffe1863.com/", "http://elenacaffe1863.com/", "http://vade-retro.fr"
rule creepy_download:
	params:
		url=lambda w: subdomain_url_map[w.target]
	output:
		'{dir}'.format(dir=permanent)+'/{target}.creepy.warc'
	shell:
		'mkdir -p {permanent}; '
		'python3 {BITEXTOR}/bin/bitextor-crawl {TLD_CRAWL} {CRAWLSIZELIMIT} {CRAWLTIMELIMIT} {CRAWLJOBS} {CRAWLTIMEOUT} {CRAWLDUMPARGS} {CONTINUECRAWL} {params.url} > {output}'

rule httrack_download:
	output:
		'{dir}'.format(dir=permanent)+'/{target}.httrack.warc'
	params:
		url=lambda w: subdomain_url_map[w.target]
	shell:
		'mkdir -p {permanent}; '
		'DIRNAME=$(mktemp -d {TMPDIR}/downloaded_websites.XXXXXX); '
		'{BITEXTOR}/bin/bitextor-downloadweb {params.url} $DIRNAME; '
		'{BITEXTOR}/bin/bitextor-webdir2warc $DIRNAME > {output}; '
		'rm -rf $DIRNAME;'

rule concat_subdomains:
	input:
		lambda w: expand('{dir}/{subdomain}.{crawler}.warc', dir=permanent, subdomain=domain_subdomain_map[w.target], crawler=CRAWLTARGET)
	output:
		"{dir}".format(dir=intermediate)+"/{target}.warc.concat"
	shell:
		'cat {input} > {output}'

rule warc2tt:
	input:
		'{target}.warc.concat'
	output:
		'{target}.tt'
	shell:
		'{BITEXTOR}/bin/bitextor-warc2tt < {input} > {output}'

rule tt2ttmime:
	input:
		'{target}.tt'
	output:
		'{target}.ttmime'
	shell:
		'{BITEXTOR}/bin/bitextor-identifyMIME < {input} > {output}'

rule tt2xtt:
	input:
		#If HTTRACK is enalbed, httrack rule is run; otherwise, download rule is applied
		'{target}.ttmime'
	output:
		'{target}.xtt'
	shell:
		'java -Dfile.encoding=UTF-8 -jar {BITEXTOR}/share/java/piped-tika.jar -x < {input} > {output}'

rule xtt2boiler:
	input:
		'{target}.xtt'
	output:
		'{target}.boiler'
	shell:
		"if [ \"{IGNOREBOILER}\" == \"1\" ]; then "
		"  java -Dfile.encoding=UTF-8 -jar {BITEXTOR}/share/java/piped-boilerpipe.jar < {input} > {output}; "
		"else "
		"  cat {input} > {output}; "
		"fi"

rule boiler2ett:
	input:
		'{target}.boiler'
	output:
		'{target}.ett'
	shell:
		'{BITEXTOR}/bin/bitextor-dedup < {input} > {output}'

rule ett2tika:
	input:
		'{target}.ett'
	output:
		'{target}.tika'
	shell:
		'java -Dfile.encoding=UTF-8 -jar {BITEXTOR}/share/java/piped-tika.jar -t < {input} > {output}'

rule ett2lett:
	input:
		'{target}.tika'
	output:
		'{target}.lett'
	shell:
		'bash {BITEXTOR}/bin/bitextor-ett2lett -l {LANG1},{LANG2} < {input} > {output}'

rule httrack2lett:
	output:
		'{target}.jlett'
	input:
		'{target}.tar'
	shell:
		'{BITEXTOR}/bin/tar2lett {input} {LANG1} {LANG2} > {output}'

rule lett2lettr:
	input:
		expand("{{target}}.{extension}", extension=LETT)
	output:
		'{target}.lettr'
	shell:
		'{BITEXTOR}/bin/bitextor-lett2lettr < {input} > {output}'

rule lettr2idx:
	input:
		'{target}.lettr'
	output:
		'{target}.idx'
	shell:
		'{BITEXTOR}/bin/bitextor-lett2idx  --lang1 {LANG1} --lang2 {LANG2} -m 15 < {input} > {output}'




#================================== DOCUMENT ALIGNMENT ==================================#

rule idx2ridx_l1tol2:
	input:
		'{target}.idx'
	output:
		'{target}.1.ridx'
	shell:
		'{BITEXTOR}/bin/bitextor-idx2ridx -d {DIC} --lang1 {LANG1} --lang2 {LANG2} < {input} > {output}'

rule idx2ridx_l2tol1:
	input:
		'{target}.idx'
	output:
		'{target}.2.ridx'
	shell:
		'{BITEXTOR}/bin/bitextor-idx2ridx -d {DIC} --lang1 {LANG2} --lang2 {LANG1}  < {input} > {output}'

rule ridx2imagesetoverlap:
	input:
		'{target}.{num}.ridx',
		'{target}.lettr'
	output:
		'{target}.{num}.imgoverlap'
	shell:
		'{BITEXTOR}/bin/bitextor-imagesetoverlap -l {wildcards.target}.lettr < {input[0]} > {output}'

rule imagesetoverlap2structuredistance:
	input:
		'{target}.{num}.imgoverlap',
		'{target}.lettr'
	output:
		'{target}.{num}.structuredistance'
	shell:
		'{BITEXTOR}/bin/bitextor-structuredistance -l {wildcards.target}.lettr < {input[0]} > {output}'

rule structuredistance2urldistance:
	input:
		'{target}.{num}.structuredistance',
		'{target}.lettr'
	output:
		'{target}.{num}.urldistance'
	shell:
		'{BITEXTOR}/bin/bitextor-urlsdistance -l {wildcards.target}.lettr < {input[0]} > {output}'

rule urldistance2mutuallylinked:
	input:
		'{target}.{num}.urldistance',
		'{target}.lettr'
	output:
		'{target}.{num}.mutuallylinked'
	shell:
		'{BITEXTOR}/bin/bitextor-mutuallylinked -l {wildcards.target}.lettr < {input[0]} > {output}'

rule mutuallylinked2urlscomparison:
	input:
		'{target}.{num}.mutuallylinked',
		'{target}.lettr'
	output:
		'{target}.{num}.urlscomparison'
	shell:
		'{BITEXTOR}/bin/bitextor-urlscomparison -l {wildcards.target}.lettr < {input[0]} > {output}'

rule urlscomparison2urlsoverlap:
	input:
		'{target}.{num}.urlscomparison',
		'{target}.lettr'
	output:
		'{target}.{num}.urlsoverlap'
	shell:
		'{BITEXTOR}/bin/bitextor-urlsetoverlap -l {wildcards.target}.lettr < {input[0]} > {output}'

rule urlsoverlap2rank:
	input:
		'{target}.{num}.urlsoverlap',
		'{target}.lettr'
	output:
		'{target}.{num}.rank'
	shell:
		'{BITEXTOR}/bin/bitextor-rank -m {BITEXTOR}/{MODEL} -w {BITEXTOR}/{WEIGHTS} < {input[0]} > {output}'

rule aligndocumentsparacrawl:
	input:
		'{target}.lett'
	output:
		'{target}.docalign.paracrawl'
	shell:
		'DOCALIGN=$(mktemp {TMPDIR}/docalign.XXXXXX); '
		'{BITEXTOR}/bin/doc_align.sh -f {input} -l {LANG2} -t "{MT_COMMAND}" -d -w $DOCALIGN > {output}'

rule aligndocumentsbitextor:
	input:
		'{target}.1.rank',
		'{target}.2.rank',
		'{target}.lettr'
	output:
		'{target}.docalign.bitextor'
	shell:
		'{BITEXTOR}/bin/bitextor-align-documents -l {input[2]} -n 1 -i converge -r /dev/null {input[0]} {input[1]} > {output}'

rule hunaligndic:
	input:
		expand("{dic}", dic=DIC)
	output:
		'{dir}/hunalign_dic'.format(dir=intermediate)
	shell:
		'tail -n +2 {input} | sed -r "s/\t/ @ x/g" > {output}'



#================================== SEGMENT ALIGNMENT ==================================#

rule alignsegments:
	input:
		'{dir}/hunalign_dic'.format(dir=intermediate),
		"{name}.docalign."+"{extension}".format(extension=DOCALIGNEXT)
	output:
		'{name}.segalign'
	shell:
		'{BITEXTOR}/bin/bitextor-align-segments -d {input[0]} -t {TMPDIR} --lang1 {LANG1} --lang2 {LANG2} {USENLTK} < {input[1]} > {output}'

rule concat_segs:
	input:
		expand("{{dir}}/{webdomain}.segalign", webdomain=domain_subdomain_map.keys())
	output:
		"{dir}/{l1}-{l2}.sent"
	shell:
		"cat {input} > {output}"


rule cleansegments:
	input:
		"{dir}/{l1}-{l2}.sent"
	output:
		"{dir}/{l1}-{l2}.segclean"
	shell:
		'{BITEXTOR}/bin/bitextor-cleantextalign -q {MINQUALITY} -m {MAXLINES} -s < {input} > {output}'

#================================== POST PROCESSING ==================================#

#NOTE: did not add zipporah since it will be deprecated in version 7 of bitextor
#TODO: Add Bicleaner, add deduplication

rule bicleaner:
	input:
		"{dir}/{l1}-{l2}.segclean"
	output:
		"{dir}/{l1}-{l2}.bicleaner.scores"
	shell:
		'python3  {BITEXTOR}/bin/bicleaner_classifier_full.py --threshold {BICLEANER_THRESHOLD} {input} {output} {BICLEANER_CONFIG}'

rule bicleanerfilter:
	input:
		"{dir}/{l1}-{l2}.bicleaner.scores"
	output:
		"{dir}/{l1}-{l2}.bicleaner"
	shell:
		'{BITEXTOR}/bin/bitextor-filterbicleaner --threshold {BICLEANER_THRESHOLD} < {input} > {output}'

rule elrc:
	input:
		"{dir}/{l1}-{l2}."+"{extension}".format(extension=BICLEANER)
	output:
		"{dir}/{l1}-{l2}.elrc"
	shell:
		'{BITEXTOR}/bin/bitextor-elrc-filtering -c "url1,url2,seg1,seg2,hunalign{BICLEANEROPTION}" -s < {input} > {output}'

rule tmx:
	input:
		"{dir}".format(dir=config["intermediate"])+"/{l1}-{l2}.elrc"
	output:
		"{dir}".format(dir=config["permanent"])+"/{l1}-{l2}.tmx"
	shell:
		"{BITEXTOR}/bin/bitextor-buildTMX --lang1 {LANG1} --lang2 {LANG2} -c url1,url2,seg1,seg2,hunalign{BICLEANEROPTION},lengthratio,numTokensSL,numTokensTL,idnumber < {input} > {output}"