require 'json'
require 'digest'

module Jekyll
  module SText
    module_function

    def hangul_tail?(s)
      c = s.to_s.strip.sub(/[\s\)\]\}\>'"”’.,!?~·\-]+\z/, '')[-1]
      !c.nil? && c.ord >= 0xAC00 && c.ord <= 0xD7A3
    end

    def batchim?(s)
      c = s.to_s.strip.sub(/[\s\)\]\}\>'"”’.,!?~·\-]+\z/, '')[-1]
      return false if c.nil?
      o = c.ord
      (o >= 0xAC00 && o <= 0xD7A3) ? ((o - 0xAC00) % 28 != 0) : false
    end

    def josa(word, with_b, without_b)
      return "#{word}#{with_b}(#{without_b})" unless hangul_tail?(word)
      word.to_s + (batchim?(word) ? with_b : without_b)
    end

    def eun_neun(w); josa(w, '은', '는'); end
    def i_ga(w); josa(w, '이', '가'); end
    def eul_reul(w); josa(w, '을', '를'); end

    def fmt(n)
      n.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
    end

    def pct(part, whole, digits = 1)
      return '-' if whole.to_f <= 0
      "#{format("%.#{digits}f", part.to_f / whole * 100)}%"
    end

    def slug(s)
      s.to_s.gsub('/', '·')
    end

    def name_slug(name, key)
      base = name.to_s.gsub(/[^\p{Hangul}\p{Alnum}]+/, '-').gsub(/-+/, '-').gsub(/\A-|-\z/, '')[0, 24]
      "#{base}-#{Digest::MD5.hexdigest(key)[0, 6]}".gsub(/-+/, '-')
    end

    def floor_label(fl)
      f = fl.to_s.strip
      return '-' if f.empty?
      return "지하#{f[/\d+/]}#{f[/\d+/] ? '층' : ''}" if f =~ /\A(지|B)/i
      f =~ /\A\d+\z/ ? "#{f}층" : f
    end

    def floor_key(fl)
      f = fl.to_s.strip
      return [2, 0] if f.empty?
      return [0, -1] if f =~ /\A(지|B)/i
      m = f.match(/\d+/)
      m ? [1, m[0].to_i] : [2, 0]
    end
  end

  class SbizGenerator < Generator
    safe true
    priority :normal

    DONG_MIN = 30
    MAX_BLD_PAGES = 12_000
    RANK_DONGS = 60

    def generate(site)
      dir = File.join(site.source, '_rawdata')
      meta = JSON.parse(File.read(File.join(dir, 'sb_meta.json'), encoding: 'utf-8'))
      nat = JSON.parse(File.read(File.join(dir, 'sb_national.json'), encoding: 'utf-8'))
      dongs = []
      sgs = []
      bizs = []
      blds = []
      Dir.glob(File.join(dir, 'sb_*.json')).sort.each do |f|
        next if f.end_with?('sb_meta.json') || f.end_with?('sb_national.json') || f.end_with?('sb_brand.json')
        d = JSON.parse(File.read(f, encoding: 'utf-8'))
        dongs.concat(d['dong'])
        sgs.concat(d['sg'])
        bizs.concat(d['biz'])
        blds.concat(d['bld'])
      end
      period = "#{meta['period'][0, 4]}.#{meta['period'][4, 2]}"
      brand_data = JSON.parse(File.read(File.join(dir, 'sb_brand.json'), encoding: 'utf-8'))
      total = meta['stores']

      sg_idx = {}
      sgs.each { |s| sg_idx[[s['do'], s['sg']]] = s }
      sml_meta = nat['meta']
      nat_sml_n = {}
      nat['sml'].each { |sml, list| nat_sml_n[sml] = list.sum { |_, c| c } }
      biz_keys = {}
      bizs.each { |b| biz_keys[[b['do'], b['sg'], b['sml']]] = b }
      dong_pages = dongs.select { |d| d['n'] >= DONG_MIN }
      dong_keys = {}
      dong_pages.each { |d| dong_keys[[d['do'], d['sg'], d['dong']]] = d }
      bld_pages = blds.sort_by { |b| [-b['n'], b['name']] }.first(MAX_BLD_PAGES)
      bld_url = {}
      bld_pages.each { |b| bld_url[[b['do'], b['sg'], b['dong'], b['name']]] = "/building/#{SText.name_slug(b['name'], "#{b['do']}|#{b['sg']}|#{b['dong']}|#{b['name']}")}/" }
      dongs_by_sg = dong_pages.group_by { |d| [d['do'], d['sg']] }
      ctx = { period: period, total: total, sg_idx: sg_idx, nat_sml_n: nat_sml_n, sml_meta: sml_meta, biz_keys: biz_keys, dong_keys: dong_keys, bld_url: bld_url }

      SbizBrand.prepare(brand_data, ctx)
      counts = Hash.new(0)
      dong_pages.each do |d|
        nb = (dongs_by_sg[[d['do'], d['sg']]] || []).reject { |x| x['dong'] == d['dong'] }.sort_by { |x| -x['n'] }.first(12)
        site.pages << DongPage.new(site, d, nb, ctx)
        counts[:dong] += 1
      end
      sgs.each do |s|
        site.pages << SgPage.new(site, s, ctx)
        counts[:sg] += 1
      end
      sgs.group_by { |s| s['do'] }.each do |do_short, list|
        site.pages << DoPage.new(site, do_short, list.sort_by { |s| -s['n'] }, ctx)
        counts[:do] += 1
      end
      bizs.each do |b|
        site.pages << BizPage.new(site, b, ctx)
        counts[:biz] += 1
      end
      nat['sml'].each do |sml, list|
        site.pages << BizIndexPage.new(site, sml, list, bizs.select { |b| b['sml'] == sml }, dong_pages, ctx)
        counts[:bizi] += 1
      end
      bld_pages.each do |b|
        nbs = blds.select { |x| x['do'] == b['do'] && x['sg'] == b['sg'] && x['dong'] == b['dong'] && x['name'] != b['name'] }.sort_by { |x| -x['n'] }.first(6)
        site.pages << BuildingPage.new(site, b, nbs, ctx)
        counts[:bld] += 1
      end

      brand_index = SbizBrand.generate(site, brand_data, ctx, counts)

      # 랭킹
      bigs = dong_pages.flat_map { |d| d['big'].map { |n, _| n } }.uniq.sort
      site.pages << RankPage.new(site, 'all', '점포가 가장 많은 동', dong_pages.sort_by { |d| -d['n'] }.first(100).map { |d| [d, d['n']] }, ctx)
      bigs.each do |bg|
        rows = dong_pages.map { |d| [d, (d['big'].find { |n, _| n == bg } || [nil, 0])[1]] }.select { |_, c| c.positive? }.sort_by { |_, c| -c }.first(RANK_DONGS)
        site.pages << RankPage.new(site, bg, "#{bg} 업종 점포가 많은 동", rows, ctx)
        counts[:rank] += 1
      end
      site.pages << RankIndexPage.new(site, bigs, ctx)

      big_names = nat['meta'].values.map { |m, b| b }.uniq.sort
      site.pages << BizHomePage.new(site, nat, ctx)
      site.data['sb_stats'] = {
        'period' => period, 'stores' => SText.fmt(total), 'dong' => SText.fmt(dong_pages.size), 'sg' => sgs.size, 'bld' => SText.fmt(bld_pages.size), 'biz' => SText.fmt(bizs.size),
        'top_dong' => dong_pages.sort_by { |d| -d['n'] }.first(12).map { |d| { 'name' => "#{d['do']} #{d['sg']} #{d['dong']}", 'url' => "/dong/#{d['do']}/#{d['sg']}/#{d['dong']}/", 'n' => SText.fmt(d['n']), 'top' => d['sml'].first(3).map { |n, _| n }.join('·') } },
        'do_rows' => sgs.group_by { |s| s['do'] }.map { |dd, l| { 'name' => dd, 'n' => SText.fmt(l.sum { |s| s['n'] }), 'sg' => l.size } }.sort_by { |r| r['name'] },
        'top_biz' => nat_sml_n.sort_by { |_, c| -c }.first(24).map { |sml, c| { 'name' => sml, 'url' => "/biz/#{SText.slug(sml)}/", 'n' => SText.fmt(c) } },
        'bigs' => big_names,
        'top_brand' => brand_data['brands'].first(18).map { |b| { 'name' => b['name'], 'url' => "/brand/#{SText.slug(b['name'])}/", 'n' => SText.fmt(b['n']), 'cat' => b['cat'] } },
        'brand_n' => brand_data['brands'].size
      }
      counts[:total] = counts.values.sum

      idx = []
      dong_pages.each { |d| idx << { 'n' => d['dong'], 't' => '동네 상권', 'l' => "#{d['do']} #{d['sg']}", 'u' => "/dong/#{d['do']}/#{d['sg']}/#{d['dong']}/" } }
      sgs.each { |s| idx << { 'n' => s['sg'], 't' => '시군구 상권', 'l' => s['do'], 'u' => "/sg/#{s['do']}/#{s['sg']}/" } }
      nat_sml_n.each_key { |sml| idx << { 'n' => sml, 't' => '업종', 'l' => '전국', 'u' => "/biz/#{SText.slug(sml)}/" } }
      brand_index.each { |x| idx << x }
      bld_pages.each { |b| idx << { 'n' => b['name'], 't' => '입점 건물', 'l' => "#{b['do']} #{b['sg']} #{b['dong']}", 'u' => bld_url[[b['do'], b['sg'], b['dong'], b['name']]] } }
      pg = PageWithoutAFile.new(site, site.source, '', 'search_index.json')
      pg.content = JSON.generate(idx)
      pg.data['layout'] = nil
      pg.data['sitemap'] = false
      site.pages << pg
      Jekyll.logger.info 'SbizGenerator:', "동 #{counts[:dong]} / 시군구 #{counts[:sg]} / 업종×시군구 #{counts[:biz]} / 업종 #{counts[:bizi]} / 건물 #{counts[:bld]} / 랭킹 #{counts[:rank] + 1} / 시도 #{counts[:do]}"
    end
  end

  class SBasePage < Page
    def setup(site, dir, layout)
      @site = site
      @base = site.source
      @dir = dir
      @name = 'index.html'
      process(@name)
      read_yaml(File.join(@base, '_layouts'), "#{layout}.html")
      data['layout'] = layout
    end

    def seo(title, desc)
      data['title'] = title
      data['description'] = desc[0, 155]
    end

    def faq(pairs)
      data['faq'] = pairs.map { |q, a| { 'q' => q, 'a' => a } }
    end

    def f(n)
      SText.fmt(n)
    end

    # [[이름, 개수]...] → 구성비 행(전체 total 기준)
    def share_rows(list, total, limit = nil)
      (limit ? list.first(limit) : list).map { |n, c| { 'name' => n, 'n' => f(c), 'share' => SText.pct(c, total), 'w' => [(c.to_f / total * 100 * 2).round, 100].min } }
    end
  end

  # ── 동 허브 ─────────────────────────────────────────
  class DongPage < SBasePage
    def initialize(site, d, neighbors, ctx)
      setup(site, "dong/#{d['do']}/#{d['sg']}/#{d['dong']}", 'dong')
      place = "#{d['do']} #{d['sg']} #{d['dong']}"
      sg = ctx[:sg_idx][[d['do'], d['sg']]]
      sg_share = {}
      (sg['sml'] || []).each { |n, c| sg_share[n] = c.to_f / sg['n'] }
      data['place'] = place
      data['doShort'] = d['do']
      data['sigungu'] = d['sg']
      data['dong'] = d['dong']
      data['period'] = ctx[:period]
      data['n'] = f(d['n'])
      data['adm'] = d['adm']
      data['bigRows'] = share_rows(d['big'], d['n'])
      data['midRows'] = share_rows(d['mid'], d['n'], 10)
      lq = []
      data['smlRows'] = d['sml'].first(25).map do |n, c|
        share = c.to_f / d['n']
        ref = sg_share[n]
        ratio = ref && ref.positive? ? (share / ref) : nil
        lq << [n, c, ratio] if ratio && c >= 8 && ratio >= 1.8
        has = ctx[:biz_keys][[d['do'], d['sg'], n]]
        { 'name' => n, 'n' => f(c), 'share' => SText.pct(c, d['n']), 'ratio' => ratio ? format('%.1f배', ratio) : '-', 'hot' => ratio && ratio >= 1.8, 'url' => has ? "/biz/#{SText.slug(n)}/#{d['do']}/#{d['sg']}/" : nil }
      end
      data['special'] = lq.sort_by { |_, _, r| -r }.first(5).map { |n, c, r| { 'name' => n, 'n' => f(c), 'ratio' => format('%.1f', r) } }
      data['blds'] = d['bld'].map { |n, c| { 'name' => n, 'n' => f(c), 'url' => ctx[:bld_url][[d['do'], d['sg'], d['dong'], n]] } }
      data['brands'] = SbizBrand.rows(d['brands'] || [], ctx, d['do'], d['sg'])
      data['neighbors'] = neighbors.map { |x| { 'name' => x['dong'], 'url' => "/dong/#{x['do']}/#{x['sg']}/#{x['dong']}/", 'n' => f(x['n']), 'top' => x['sml'].first(2).map { |n, _| n }.join('·') } }
      rank = ctx[:dong_keys].values.select { |x| x['do'] == d['do'] && x['sg'] == d['sg'] }.sort_by { |x| -x['n'] }.index { |x| x['dong'] == d['dong'] }.to_i + 1
      data['rank'] = rank
      data['sgDongs'] = ctx[:dong_keys].values.count { |x| x['do'] == d['do'] && x['sg'] == d['sg'] }
      data['landUrl'] = "https://wooaland.wooahouse.com/shop/#{d['do']}/#{d['sg']}/#{d['dong']}/"
      data['aaptUrl'] = "https://wooaapt.wooahouse.com/region/#{d['do']}/#{d['sg']}/#{d['dong']}/"
      data['hakUrl'] = "https://wooahakgun.wooahouse.com/region/#{d['do']}/#{d['sg']}/#{d['dong']}/"
      data['townUrl'] = "https://wooatown.wooahouse.com/"

      top1 = d['sml'][0]
      top2 = d['sml'][1]
      big0 = d['big'][0]
      s = +"#{place}에는 #{ctx[:period]} 기준 점포 #{f(d['n'])}곳이 영업 중인 것으로 집계됩니다(#{d['sg']} 안에서 #{rank}위). "
      s << "업종 대분류로는 #{big0[0]}이 #{f(big0[1])}곳(#{SText.pct(big0[1], d['n'], 0)})으로 가장 많고, " if big0
      s << "세부 업종으로는 #{top1[0]} #{f(top1[1])}곳#{top2 ? ", #{top2[0]} #{f(top2[1])}곳" : ''} 순입니다. " if top1
      s << "#{d['sg']} 평균과 비교해 #{data['special'].first(2).map { |x| "#{x['name']}(#{x['ratio']}배)" }.join(', ')} 업종이 유독 많은 동네입니다. " unless data['special'].empty?
      s << "점포가 가장 많이 입점한 건물은 #{d['bld'][0][0]}(#{f(d['bld'][0][1])}곳)입니다." if d['bld'] && !d['bld'].empty?
      data['summary'] = s
      seo("#{place} 상권분석 - 업종별 점포 수·특화 업종 #{ctx[:period][0, 4]}", "#{place} 상권: 점포 #{f(d['n'])}곳, #{top1 ? "#{top1[0]} #{f(top1[1])}곳 등 " : ''}업종별 점포 수와 #{d['sg']} 대비 특화 업종, 입점 많은 건물.")
      pairs = []
      pairs << ["#{place}에는 어떤 업종이 가장 많나요?", top1 ? "#{ctx[:period]} 기준 #{top1[0]}이 #{f(top1[1])}곳(#{SText.pct(top1[1], d['n'])})으로 가장 많고#{top2 ? ", 그다음은 #{top2[0]} #{f(top2[1])}곳입니다" : '입니다'}." : '집계된 업종이 없습니다.']
      pairs << ['특화 업종은 어떻게 계산했나요?', "이 동네 점포 중 해당 업종의 비중을 #{d['sg']} 전체 평균 비중으로 나눈 값입니다. 1.8배 이상이면서 점포가 8곳 이상인 업종만 표시했으며, 값이 클수록 이 동네에 유독 몰려 있다는 뜻입니다."]
      pairs << ['점포 수는 실제와 다를 수 있나요?', '소상공인시장진흥공단이 분기마다 공개하는 상가업소 자료를 집계한 것이라 조사 이후 개업·폐업·이전은 반영되지 않습니다. 창업이나 입지를 정하기 전에는 현장 확인과 별도 상권 조사를 병행하세요.']
      faq(pairs)
    end
  end

  # ── 시군구 허브 ─────────────────────────────────────
  class SgPage < SBasePage
    def initialize(site, s, ctx)
      setup(site, "sg/#{s['do']}/#{s['sg']}", 'sg')
      place = "#{s['do']} #{s['sg']}"
      data['place'] = place
      data['doShort'] = s['do']
      data['sigungu'] = s['sg']
      data['period'] = ctx[:period]
      data['n'] = f(s['n'])
      data['nd'] = s['nd']
      data['bigRows'] = share_rows(s['big'], s['n'])
      nat_total = ctx[:total].to_f
      data['smlRows'] = s['sml'].first(40).map do |n, c|
        nat_share = (ctx[:nat_sml_n][n] || 0) / nat_total
        share = c.to_f / s['n']
        ratio = nat_share.positive? ? share / nat_share : nil
        has = ctx[:biz_keys][[s['do'], s['sg'], n]]
        { 'name' => n, 'n' => f(c), 'share' => SText.pct(c, s['n']), 'ratio' => ratio ? format('%.1f배', ratio) : '-', 'hot' => ratio && ratio >= 1.4, 'url' => has ? "/biz/#{SText.slug(n)}/#{s['do']}/#{s['sg']}/" : nil }
      end
      data['dongRows'] = s['dongs'].map do |n, c|
        dk = ctx[:dong_keys][[s['do'], s['sg'], n]]
        { 'name' => n, 'n' => f(c), 'share' => SText.pct(c, s['n']), 'url' => dk ? "/dong/#{s['do']}/#{s['sg']}/#{n}/" : nil, 'top' => dk ? dk['sml'].first(2).map { |x, _| x }.join('·') : '' }
      end
      data['brands'] = SbizBrand.rows(s['brands'] || [], ctx, s['do'], s['sg'])
      data['blds'] = s['bld'].map { |n, dg, c| { 'name' => n, 'dong' => dg, 'n' => f(c), 'url' => ctx[:bld_url][[s['do'], s['sg'], dg, n]] } }
      data['landUrl'] = "https://wooaland.wooahouse.com/shop/#{s['do']}/#{s['sg']}/"
      data['aaptUrl'] = "https://wooaapt.wooahouse.com/region/#{s['do']}/#{s['sg']}/"
      top1 = s['sml'][0]
      top2 = s['sml'][1]
      top3 = s['sml'][2]
      s2 = +"#{place}에는 #{ctx[:period]} 기준 점포 #{f(s['n'])}곳이 있고, #{s['nd']}개 법정동에 분포합니다. "
      s2 << "가장 많은 업종은 #{top1[0]}(#{f(top1[1])}곳)#{top2 ? ", #{top2[0]}(#{f(top2[1])}곳)" : ''}#{top3 ? ", #{top3[0]}(#{f(top3[1])}곳)" : ''} 순입니다. " if top1
      s2 << "점포가 가장 몰린 동네는 #{s['dongs'][0][0]}(#{f(s['dongs'][0][1])}곳, #{SText.pct(s['dongs'][0][1], s['n'], 0)})입니다." if s['dongs'] && !s['dongs'].empty?
      data['summary'] = s2
      seo("#{place} 상권분석 - 동네별 점포 수·업종 현황 #{ctx[:period][0, 4]}", "#{place} 점포 #{f(s['n'])}곳의 업종 구성과 동네별 점포 수. #{top1 ? "#{top1[0]} #{f(top1[1])}곳 등 " : ''}업종별 현황과 입점 많은 건물.")
      faq([["#{s['sg']}에는 점포가 몇 곳 있나요?", "#{ctx[:period]} 기준 소상공인시장진흥공단 상가업소 자료에 #{f(s['n'])}곳이 집계됩니다(#{s['nd']}개 법정동). 동네별 현황은 아래 표에서 확인하세요."],
           ["#{s['sg']}에서 가장 많은 업종은 무엇인가요?", top1 ? "#{top1[0]}이 #{f(top1[1])}곳(#{SText.pct(top1[1], s['n'])})으로 가장 많고#{top2 ? ", #{top2[0]} #{f(top2[1])}곳이 뒤를 잇습니다" : '입니다'}." : '집계된 업종이 없습니다.']])
    end
  end

  class DoPage < SBasePage
    def initialize(site, do_short, list, ctx)
      setup(site, "do/#{do_short}", 'do')
      data['doShort'] = do_short
      data['period'] = ctx[:period]
      n = list.sum { |s| s['n'] }
      data['n'] = f(n)
      data['sgRows'] = list.map { |s| { 'name' => s['sg'], 'url' => "/sg/#{s['do']}/#{s['sg']}/", 'n' => f(s['n']), 'nd' => s['nd'], 'top' => s['sml'].first(3).map { |x, _| x }.join('·') } }
      data['summary'] = "#{do_short}에는 #{ctx[:period]} 기준 #{list.size}개 시군구에 점포 #{f(n)}곳이 집계됩니다. 시군구를 선택하면 동네별 점포 수와 업종 구성을 볼 수 있습니다."
      seo("#{do_short} 상권분석 - 시군구별 점포 수·업종 #{ctx[:period][0, 4]}", "#{do_short} 점포 #{f(n)}곳. 시군구별 점포 수와 주요 업종, 동네별 상권분석 바로가기.")
    end
  end

  # ── 업종 × 시군구 ───────────────────────────────────
  class BizPage < SBasePage
    def initialize(site, b, ctx)
      setup(site, "biz/#{SText.slug(b['sml'])}/#{b['do']}/#{b['sg']}", 'biz')
      place = "#{b['do']} #{b['sg']}"
      sg = ctx[:sg_idx][[b['do'], b['sg']]]
      nat_share = (ctx[:nat_sml_n][b['sml']] || 0).to_f / ctx[:total] * 100
      ratio = nat_share.positive? ? b['share'] / nat_share : nil
      data['place'] = place
      data['doShort'] = b['do']
      data['sigungu'] = b['sg']
      data['sml'] = b['sml']
      data['smlGa'] = SText.i_ga(b['sml'])
      data['mid'] = b['mid']
      data['big'] = b['big']
      data['period'] = ctx[:period]
      data['n'] = f(b['n'])
      data['share'] = format('%.2f%%', b['share'])
      data['natShare'] = format('%.2f%%', nat_share)
      data['ratio'] = ratio ? format('%.1f', ratio) : nil
      data['rank'] = b['rank']
      data['sgN'] = f(sg['n'])
      data['dongRows'] = b['dongs'].map do |n, c|
        dk = ctx[:dong_keys][[b['do'], b['sg'], n]]
        { 'name' => n, 'n' => f(c), 'share' => SText.pct(c, b['n']), 'w' => [(c.to_f / b['n'] * 100).round, 100].min, 'url' => dk ? "/dong/#{b['do']}/#{b['sg']}/#{n}/" : nil }
      end
      data['others'] = sg['sml'].select { |n, _| n != b['sml'] && ctx[:sml_meta][n] && ctx[:sml_meta][n][0] == b['mid'] }.first(10).map do |n, c|
        has = ctx[:biz_keys][[b['do'], b['sg'], n]]
        { 'name' => n, 'n' => f(c), 'url' => has ? "/biz/#{SText.slug(n)}/#{b['do']}/#{b['sg']}/" : nil }
      end
      data['natUrl'] = "/biz/#{SText.slug(b['sml'])}/"
      data['sgUrl'] = "/sg/#{b['do']}/#{b['sg']}/"
      top1 = b['dongs'].first
      s = +"#{place}에는 #{ctx[:period]} 기준 #{b['sml']} 점포가 #{f(b['n'])}곳 있습니다(#{b['sg']} 전체 점포의 #{data['share']}, 시군구 내 업종 #{b['rank']}위). "
      s << "전국 평균 비중(#{data['natShare']})의 #{data['ratio']}배 수준입니다. " if ratio
      s << "#{top1[0]}에 #{f(top1[1])}곳(#{SText.pct(top1[1], b['n'], 0)})으로 가장 많이 모여 있습니다." if top1
      data['summary'] = s
      seo("#{place} #{b['sml']} 현황 - 점포 #{f(b['n'])}곳·동네별 분포 #{ctx[:period][0, 4]}", "#{place} #{b['sml']} #{f(b['n'])}곳(#{b['sg']} 점포의 #{data['share']}). 동네별 분포와 같은 업종군 현황, 창업 전 참고 자료.")
      faq([["#{place}에는 #{SText.i_ga(b['sml'])} 몇 곳 있나요?", "#{ctx[:period]} 기준 소상공인시장진흥공단 상가업소 자료에 #{f(b['n'])}곳이 집계됩니다. 조사 이후 개업·폐업은 반영되지 않을 수 있습니다."],
           ["#{SText.i_ga(b['sml'])} 가장 많은 동네는 어디인가요?", top1 ? "#{top1[0]}에 #{f(top1[1])}곳이 있어 가장 많습니다. 아래 표에서 동네별 분포를 확인하세요." : '집계된 동네가 없습니다.'],
           ["#{b['sml']} 창업 전에 무엇을 확인하나요?", '동네 점포 수는 경쟁 강도의 참고 지표일 뿐입니다. 임대료, 유동인구, 배후 세대수와 실제 매출은 이 자료에 없으므로 현장 방문과 상권 분석 도구로 별도 확인하세요.']])
    end
  end

  # ── 업종(전국) ──────────────────────────────────────
  class BizIndexPage < SBasePage
    def initialize(site, sml, do_list, biz_rows, dong_pages, ctx)
      setup(site, "biz/#{SText.slug(sml)}", 'bizindex')
      mid, big = ctx[:sml_meta][sml]
      n = ctx[:nat_sml_n][sml]
      data['sml'] = sml
      data['smlGa'] = SText.i_ga(sml)
      data['mid'] = mid
      data['big'] = big
      data['period'] = ctx[:period]
      data['n'] = f(n)
      data['share'] = format('%.2f%%', n.to_f / ctx[:total] * 100)
      data['doRows'] = do_list.map { |d, c| { 'name' => d, 'n' => f(c), 'share' => SText.pct(c, n) } }
      data['topSg'] = biz_rows.sort_by { |b| -b['n'] }.first(20).map { |b| { 'name' => "#{b['do']} #{b['sg']}", 'url' => "/biz/#{SText.slug(sml)}/#{b['do']}/#{b['sg']}/", 'n' => f(b['n']), 'share' => format('%.2f%%', b['share']) } }
      data['shareSg'] = biz_rows.select { |b| b['n'] >= 30 }.sort_by { |b| -b['share'] }.first(10).map { |b| { 'name' => "#{b['do']} #{b['sg']}", 'url' => "/biz/#{SText.slug(sml)}/#{b['do']}/#{b['sg']}/", 'n' => f(b['n']), 'share' => format('%.2f%%', b['share']) } }
      td = dong_pages.map { |d| [d, (d['sml'].find { |x, _| x == sml } || [nil, 0])[1]] }.select { |_, c| c.positive? }.sort_by { |_, c| -c }.first(20)
      data['topDong'] = td.map { |d, c| { 'name' => "#{d['sg']} #{d['dong']}", 'url' => "/dong/#{d['do']}/#{d['sg']}/#{d['dong']}/", 'n' => f(c) } }
      data['sgUrlList'] = []
      s = +"전국에는 #{ctx[:period]} 기준 #{sml}(#{big} > #{mid}) 점포가 #{f(n)}곳 집계됩니다(전체 점포의 #{data['share']}). "
      s << "시도별로는 #{do_list[0][0]}(#{f(do_list[0][1])}곳), #{do_list[1] ? "#{do_list[1][0]}(#{f(do_list[1][1])}곳)" : ''} 순입니다. " if do_list[0]
      data['summary'] = s
      seo("전국 #{sml} 현황 - 시도·시군구별 점포 수 #{ctx[:period][0, 4]}", "전국 #{sml} 점포 #{f(n)}곳. 시도·시군구·동네별 분포와 점포가 가장 많은 지역 TOP.")
      faq([["전국에 #{sml}은 몇 곳 있나요?", "#{ctx[:period]} 기준 소상공인시장진흥공단 상가업소 자료에서 #{f(n)}곳이 집계됩니다."],
           ["#{SText.i_ga(sml)} 가장 많은 지역은 어디인가요?", data['topSg'].first ? "시군구 기준으로 #{data['topSg'].first['name']}에 #{data['topSg'].first['n']}곳이 있어 가장 많습니다." : '집계된 지역이 없습니다.']])
    end
  end

  class BizHomePage < SBasePage
    def initialize(site, nat, ctx)
      setup(site, 'biz', 'bizindex')
      data['home'] = true
      data['period'] = ctx[:period]
      groups = {}
      nat['meta'].each { |sml, (mid, big)| ((groups[big] ||= {})[mid] ||= []) << [sml, ctx[:nat_sml_n][sml] || 0] }
      data['groups'] = groups.sort_by { |_, ms| -ms.values.flatten(1).sum { |_, c| c } }.map do |big, ms|
        { 'name' => big, 'n' => f(ms.values.flatten(1).sum { |_, c| c }), 'mids' => ms.sort_by { |_, l| -l.sum { |_, c| c } }.map { |mid, l| { 'name' => mid, 'n' => f(l.sum { |_, c| c }), 'smls' => l.sort_by { |_, c| -c }.map { |sml, c| { 'name' => sml, 'n' => f(c), 'url' => "/biz/#{SText.slug(sml)}/" } } } } }
      end
      seo("업종별 점포 수 - 전국 업종 분류 목록 #{ctx[:period][0, 4]}", "전국 상가업소를 대·중·소분류 업종별로 정리. 카페·치킨·편의점·미용실·학원 등 업종별 점포 수와 지역별 분포.")
    end
  end

  # ── 입점 건물 ───────────────────────────────────────
  class BuildingPage < SBasePage
    def initialize(site, b, neighbors, ctx)
      key = "#{b['do']}|#{b['sg']}|#{b['dong']}|#{b['name']}"
      setup(site, "building/#{SText.name_slug(b['name'], key)}".sub(%r{\A/}, ''), 'building')
      place = "#{b['do']} #{b['sg']} #{b['dong']}"
      data['bName'] = b['name']
      data['place'] = place
      data['doShort'] = b['do']
      data['sigungu'] = b['sg']
      data['dong'] = b['dong']
      data['road'] = b['road']
      data['period'] = ctx[:period]
      data['n'] = f(b['n'])
      data['bigRows'] = share_rows(b['big'], b['n'])
      data['smlRows'] = share_rows(b['sml'], b['n'], 8)
      stores = b['st'].sort_by { |nm, fl, _| [SText.floor_key(fl), nm] }
      data['stores'] = stores.map { |nm, fl, sml| { 'name' => nm, 'floor' => SText.floor_label(fl), 'sml' => sml } }
      data['shown'] = stores.size
      data['more'] = [b['n'] - stores.size, 0].max
      data['dongUrl'] = ctx[:dong_keys][[b['do'], b['sg'], b['dong']]] ? "/dong/#{b['do']}/#{b['sg']}/#{b['dong']}/" : nil
      data['neighbors'] = neighbors.map { |x| { 'name' => x['name'], 'n' => f(x['n']), 'url' => ctx[:bld_url][[x['do'], x['sg'], x['dong'], x['name']]] } }
      top = b['sml'].first(3).map { |n, c| "#{n} #{f(c)}곳" }.join(', ')
      data['summary'] = "#{SText.eun_neun(b['name'])} #{place}#{b['road'].to_s.empty? ? '' : "(#{b['road']})"}에 있는 건물로, #{ctx[:period]} 기준 점포 #{f(b['n'])}곳이 입점해 있는 것으로 집계됩니다. 업종은 #{top} 순으로 많습니다."
      seo("#{b['name']} 입점 업체 목록 - #{place} 상가 #{f(b['n'])}곳", "#{place} #{b['name']}에 입점한 점포 #{f(b['n'])}곳의 층별 상호와 업종. #{top}.")
      faq([["#{b['name']}에는 어떤 가게가 입점해 있나요?", "#{ctx[:period]} 기준 #{f(b['n'])}곳이 집계되며 #{top} 순으로 많습니다. 아래 표에서 층별 상호와 업종을 확인할 수 있습니다."],
           ['입점 목록은 최신인가요?', '소상공인시장진흥공단이 분기마다 공개하는 자료이므로 최근 개업·폐업·이전은 반영되지 않았을 수 있습니다. 방문 전 전화나 지도 앱으로 영업 여부를 확인하세요.']])
    end
  end

  # ── 랭킹 ────────────────────────────────────────────
  class RankPage < SBasePage
    def initialize(site, key, title, rows, ctx)
      setup(site, key == 'all' ? 'rank/all' : "rank/#{key}", 'rank')
      data['key'] = key
      data['rankTitle'] = title
      data['period'] = ctx[:period]
      data['rows'] = rows.each_with_index.map { |(d, c), i| { 'rank' => i + 1, 'name' => "#{d['do']} #{d['sg']} #{d['dong']}", 'url' => "/dong/#{d['do']}/#{d['sg']}/#{d['dong']}/", 'n' => f(c), 'total' => f(d['n']), 'top' => d['sml'].first(2).map { |n, _| n }.join('·') } }
      data['count'] = rows.size
      data['summary'] = "#{ctx[:period]} 기준 소상공인시장진흥공단 상가업소 자료로 만든 순위입니다. 점포 #{DongRankNote.text(key)} 상위 #{rows.size}개 동네를 정리했으며, 점포 30곳 미만인 동네는 제외했습니다."
      seo("#{title} TOP #{rows.size} (#{ctx[:period][0, 4]})", "#{title} 순위: 전국 법정동 기준 상위 #{rows.size}곳의 점포 수와 주요 업종.")
    end
  end

  module DongRankNote
    module_function

    def text(key)
      key == 'all' ? '수' : '중 해당 업종 수'
    end
  end

  class RankIndexPage < SBasePage
    def initialize(site, bigs, ctx)
      setup(site, 'rank', 'rank')
      data['index'] = true
      data['period'] = ctx[:period]
      data['bigs'] = bigs
      seo("동네 상권 랭킹 - 점포·업종이 가장 많은 동네 #{ctx[:period][0, 4]}", '점포가 가장 많은 동네와 음식·소매·교육 등 업종별로 점포가 몰린 동네 순위. 전국 법정동 기준.')
    end
  end

  # 사이트맵: 5만 건 한도 때문에 40,000건씩 분할 + 인덱스
  class SbizSitemapGenerator < Generator
    safe true
    priority :lowest
    CHUNK = 40_000

    def generate(site)
      urls = site.pages.reject { |p| p.url.to_s.end_with?('.json', '.xml', '.txt', '.js', '.css') || p.url.to_s == '/404.html' || p.data['sitemap'] == false }.map { |p| p.url }.uniq
      base = site.config['url'].to_s
      chunks = urls.each_slice(CHUNK).to_a
      chunks.each_with_index do |c, idx|
        body = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        c.each { |u| body << "  <url><loc>#{base}#{u}</loc></url>\n" }
        body << "</urlset>\n"
        site.pages << raw_page(site, "sitemap-#{idx + 1}.xml", body)
      end
      index = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
      chunks.each_index { |idx| index << "  <sitemap><loc>#{base}/sitemap-#{idx + 1}.xml</loc></sitemap>\n" }
      index << "</sitemapindex>\n"
      site.pages << raw_page(site, 'sitemap.xml', index)
      Jekyll.logger.info 'SbizSitemap:', "#{urls.size}개 URL → #{chunks.size}개 사이트맵"
    end

    private

    def raw_page(site, name, content)
      pg = PageWithoutAFile.new(site, site.source, '', name)
      pg.content = content
      pg.data['layout'] = nil
      pg.data['sitemap'] = false
      pg
    end
  end
end
