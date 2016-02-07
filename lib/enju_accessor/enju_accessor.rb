#!/usr/bin/env ruby
require 'rest-client'
require 'text_sentencer'

# An instance of this class holds the parsing result of a natural language query as anlyzed by Enju.
class EnjuAccessor
  def initialize
    @enju_cgi = RestClient::Resource.new "http://bionlp.dbcls.jp/enju"
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
      response.split(/\r?\n/).each_with_index do |t, i|  # for each token analysis
        dat = t.split(/\t/, 7)
        token = Hash.new
        token[:idx]  = i - 1   # use 0-oriented index
        token[:word] = dat[1]
        token[:base] = dat[2]
        token[:pos]  = dat[3]
        token[:cat]  = dat[4]
        token[:type] = dat[5]
        token[:args] = dat[6].split.collect{|a| type, ref = a.split(':'); [type, ref.to_i - 1]} if dat[6]
        @tokens << token
      end

      @root = @tokens.shift[:args][0][1]

      # get span offsets
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
    segments = TextSentencer.segment(text)

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
  enju = EnjuAccessor.new
  annotation = enju.get_annotation_text(
"Foxp3 Represses Retroviral Transcription by Targeting Both NF-kappaB and CREB Pathways
Forkhead box (Fox)/winged-helix transcription factors regulate multiple aspects of immune responsiveness and Foxp3 is recognized as an essential functional marker of regulatory T cells. Herein we describe downstream signaling pathways targeted by Foxp3 that may negatively impact retroviral pathogenesis. Overexpression of Foxp3 in HEK 293T and purified CD4+ T cells resulted in a dose-dependent and time-dependent decrease in basal levels of nuclear factor-kappaB (NF-kappaB) activation. Deletion of the carboxyl-terminal forkhead (FKH) domain, critical for nuclear localization and DNA-binding activity, abrogated the ability of Foxp3 to suppress NF-kappaB activity in HEK 293T cells, but not in Jurkat or primary human CD4+ T cells. We further demonstrate that Foxp3 suppressed the transcription of two human retroviral promoters (HIV-1 and human T cell lymphotropic virus type I [HTLV-I]) utilizing NF-kappaB-dependent and NF-kappaB-independent mechanisms. Examination of the latter identified the cAMP-responsive element binding protein (CREB) pathway as a target of Foxp3. Finally, comparison of the percent Foxp3+CD4+CD25+ T cells to the HTLV-I proviral load in HTLV-I-infected asymptomatic carriers and patients with HTLV-I-associated myelopathy/tropical spastic paraparesis suggested that high Foxp3 expression is associated with low proviral load and absence of disease. These results suggest an expanded role for Foxp3 in regulating NF-kappaB- and CREB-dependent cellular and viral gene expression."
  )
  p annotation


  ARGF.each do |line|
    annotation = enju.get_annotation_sentence(line.chomp)
    p annotation
  end
end
