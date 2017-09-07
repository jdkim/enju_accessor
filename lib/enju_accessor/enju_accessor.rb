#!/usr/bin/env ruby
require 'rest-client'
require 'text_sentencer'

# An instance of this class holds the parsing result of a natural language query as anlyzed by Enju.
class EnjuAccessor
  def initialize
    @enju_cgi = RestClient::Resource.new "http://bionlp.dbcls.jp/enju"
    @sentencer = TextSentencer.new
    @tid_base, @rid_base = 0, 0
  end

  def get_parse (sentence)
    begin
      response = @enju_cgi.get :params => {:sentence=>sentence, :format=>'conll'}
    rescue => e
      raise IOError, "Enju CGI server does not respond."
    end

    case response.code
    when 200             # 200 means success
      raise "Empty input." if response =~/^Empty line/
      response = response.encode("ASCII-8BIT").force_encoding("UTF-8")

      @tokens = []

      # response is a parsing result in CONLL format.
      response.to_s.split(/\r?\n/).each_with_index do |t, i|  # for each token analysis
        dat = t.split(/\t/, 7)
        token = Hash.new
        token[:idx]  = i - 1   # use 0-oriented index
        token[:word] = dat[1]
        token[:base] = dat[2]
        token[:pos]  = dat[3]
        token[:cat]  = dat[4]
        token[:type] = dat[5]
        if dat[6]
          token[:args] = dat[6].split.collect{|a| type, ref = a.split(':'); [type, ref.to_i - 1]}
        end
        @tokens << token
      end

      # @root = @tokens.shift[:args][0][1]

      # get span offsets
      top = @tokens.shift
      i = 0
      @tokens.each do |token|
        i += 1 until sentence[i] !~ /[ \t\n]/
        token[:beg] = i
        token[:end] = i + token[:word].length
        i = token[:end]
      end
    else
      raise IOError, "Enju CGI server dose not respond."
    end
    @tokens
  end

  def get_annotation_sentence (sentence, offset_base = 0, mode = '')
    @tid_base, @rid_base = 0, 0 unless mode == 'continue'

    get_parse(sentence)

    denotations = []
    idx_last = 0
    @tokens.each do |token|
      denotations << {:id => 'T' + (token[:idx] + @tid_base).to_s, :span => {:begin => token[:beg] + offset_base, :end => token[:end] + offset_base}, :obj => token[:cat]}
      idx_last = token[:idx]
    end

    relations = []
    rid_num = @rid_base
    @tokens.each do |token|
      if token[:args]
        token[:args].each do |type, arg|
          if arg >= 0
            relations << {:id => 'R' + rid_num.to_s, :subj => 'T' + (arg + @tid_base).to_s, :obj => 'T' + (token[:idx] + @tid_base).to_s, :pred => type.downcase + 'Of'}
            rid_num += 1
          end
        end
      end
    end

    @tid_base = @tid_base + idx_last + 1
    @rid_base = rid_num

    {:denotations => denotations, :relations => relations}
  end

  def get_annotation_text (text)
    segments = @sentencer.segment(text)

    denotations, relations = [], []
    segments.each_with_index do |s, i|
      mode = (i == 0)? nil : 'continue'
      annotation = get_annotation_sentence(text[s[0]...s[1]], s[0], mode)
      denotations += annotation[:denotations]
      relations += annotation[:relations]
    end

    {:text=> text, :denotations => denotations, :relations => relations}
  end

end


if __FILE__ == $0
  require 'json'
  require 'optparse'

  outdir = 'out'

  optparse = OptionParser.new do |opts|
    opts.banner = "Usage: enju_accessor.rb [option(s)] a-directory-with-txt-files"

    opts.on('-o', '--output directory', "specifies the output directory (default: '#{outdir}')") do |d|
      outdir = d
    end

    opts.on('-h', '--help', 'displays this screen') do
      puts opts
      exit
    end
  end

  optparse.parse!
  unless ARGV.length == 1
    puts optparse
    exit
  end

  indir = ARGV[0]
  puts "# input directory: #{indir}"
  puts "# output directory: #{outdir}"

  if !outdir.nil? && !File.exists?(outdir)
    Dir.mkdir(outdir)
    puts "# output directory (#{outdir}) created."
  end

  enju = EnjuAccessor.new

  count_files = 0

  Dir.foreach(indir) do |infile|
    next unless infile.end_with?('.txt')
    pmid = File.basename(infile, ".txt")
    outfile = outdir + '/' + pmid + '.json' unless outdir.nil?

    count_files += 1
    print "#{pmid}\t#{count_files}\r"

    text = File.read(indir + '/' + infile)
    annotation = enju.get_annotation_text(text)
    annotation[:sourcedb] = 'PubMed'
    annotation[:sourceid] = pmid

    File.write(outfile, annotation.to_json)
  end

  puts "# count files: #{count_files}"
end
