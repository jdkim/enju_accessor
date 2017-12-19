#!/usr/bin/env ruby
require 'rest-client'
require 'text_sentencer'
require 'nokogiri'

# An instance of this class holds the parsing result of a natural language query as anlyzed by Enju.
class EnjuAccessor
  def initialize(enju_cgi_url)
    @enju_cgi = RestClient::Resource.new(enju_cgi_url)
    @sentencer = TextSentencer.new
    @tid_base, @rid_base = 0, 0
  end

  def get_parse (sentence)
    begin
      response = @enju_cgi.get :params => {:sentence=>sentence, :format=>'so'}
    rescue => e
      raise IOError, "Abnormal behavior of the Enju CGI server: #{e.message}."
    end

    parse = case response.code
    when 200             # 200 means success
      raise "Empty input." if response =~/^Empty line/
      r = response.encode("ASCII-8BIT").force_encoding("UTF-8").to_s
      read_parse(sentence, r)
    else
      raise IOError, "Abnormal response from the Enju CGI server."
    end

    parse
  end

  def read_parse (sentence, r)
    toks = {}
    cons = {}

    adjustment = 0

    # r is a parsing result in SO format.
    lines = r.split(/\r?\n/)

    idx = 0
    lines.each do |line|  # for each line of analysis
      b, e, attr_str = line.split(/\t/)
      b = b.to_i
      e = e.to_i

      node = Nokogiri::HTML.parse('<node ' + attr_str + '>')
      attrs = node.css('node').first.to_h

      if attrs['tok'] == ""
        base = attrs['base']

        b += adjustment
        base.each_char{|c| adjustment += (1 - c.bytesize) if c !~ /\p{ASCII}/}
        e += adjustment

        id = attrs['id']
        pos = attrs['pos']
        pos = attrs['base'] if [',', '.', ':', '(', ')', '``', '&apos;&apos;'].include?(pos)
        pos.sub!('$', '-DOLLAR-')
        pos = '-COLON-' if pos == 'HYPH'
        toks[id] = {beg: b, end:e, word:sentence[b ... e], idx:idx, base:base, pos:pos, cat:attrs['cat'], args:{}}
        toks[id][:args][:arg1] = attrs['arg1'] if attrs['arg1']
        toks[id][:args][:arg2] = attrs['arg2'] if attrs['arg2']
        toks[id][:args][:arg3] = attrs['arg3'] if attrs['arg3']
        toks[id][:args][:mod] = attrs['mod'] if attrs['mod']
        idx += 1
      end
    end

    lines.each do |line|  # for each line of analysis
      b, e, attr_str = line.split(/\t/)
      b = b.to_i
      e = e.to_i

      node = Nokogiri::HTML.parse('<node ' + attr_str + '>')
      attrs = node.css('node').first.to_h

      if attrs['cons'] == ""
        id = attrs['id']
        head = attrs['head']
        sem_head = attrs['sem_head']
        cat = attrs['cat']
        cons[id] = {head:head, sem_head: sem_head, cat:cat}
      end
    end

    # puts sentence
    # puts toks.map{|t| t.to_s}.join("\n")
    # puts cons.map{|c| c.to_s}.join("\n")
    # puts "-----"
    # exit

    [toks, cons]
  end

  def parse_sentence (sentence, offset_base = 0, mode = '')
    @tid_base, @rid_base = 0, 0 unless mode == 'continue'

    toks, cons = get_parse(sentence)

    denotations = []
    tid_mapping = {}
    idx_last = 0
    toks.each do |id, tok|
      id = tid_mapping[id] = 'T' + (tok[:idx] + @tid_base).to_s
      denotations << {id:id, span:{begin: tok[:beg] + offset_base, end: tok[:end] + offset_base}, obj: tok[:pos]}
      idx_last = tok[:idx]
    end

    # puts toks.map{|t| t.to_s}.join("\n")

    cons.each do |id, con|
      thead = con[:sem_head]
      thead = cons[thead][:sem_head] until thead.start_with?('t')
      con[:thead] = thead
    end

    relations = []
    rid_num = @rid_base
    toks.each do |id, tok|
      unless tok[:args].empty?
        tok[:args].each do |type, arg|
          arg = cons[arg][:thead] if arg.start_with?('c')
          next if tid_mapping[arg].nil?
          relations << {id: 'R' + rid_num.to_s, subj: tid_mapping[arg], obj: tid_mapping[id], pred: type.to_s.downcase + 'Of'}
          rid_num += 1
        end
      end
    end

    @tid_base = @tid_base + idx_last + 1
    @rid_base = rid_num

    {:denotations => denotations, :relations => relations}
  end

  def tag_sentence (sentence, offset_base = 0, mode = '')
    @id_base = 0 unless mode == 'continue'

    toks, cons = get_parse(sentence)

    denotations = []
    idx_last = 0
    toks.each do |id, tok|
      denotations << {id: 'P' + (tok[:idx] + @id_base).to_s, span: {begin: tok[:beg] + offset_base, end: tok[:end] + offset_base}, obj: tok[:pos]}
      denotations << {id: 'B' + (tok[:idx] + @id_base).to_s, span: {begin: tok[:beg] + offset_base, end: tok[:end] + offset_base}, obj: tok[:base]}
      idx_last = tok[:idx]
    end

    @id_base = @id_base + idx_last + 1

    {:denotations => denotations}
  end

  def parse_text (text)
    segments = @sentencer.segment(text)

    denotations, relations = [], []
    segments.each_with_index do |s, i|
      mode = (i == 0)? nil : 'continue'
      annotation = parse_sentence(text[s[0]...s[1]], s[0], mode)
      denotations += annotation[:denotations]
      relations += annotation[:relations]
    end

    {:text=> text, :denotations => denotations, :relations => relations}
  end

  def tag_text (text)
    segments = @sentencer.segment(text)

    denotations = []
    segments.each_with_index do |s, i|
      mode = (i == 0)? nil : 'continue'
      annotation = tag_sentence(text[s[0]...s[1]], s[0], mode)
      denotations += annotation[:denotations]
    end

    {:text=> text, :denotations => denotations}
  end

end
