# 브랜드(프랜차이즈) 페이지: sbiz_generator.rb 이후에 로드되도록 파일명을 sbiz_zbrand.rb 로 둔다.
module Jekyll
  module SbizBrand
    module_function

    # 동·시군구 페이지가 브랜드 링크를 만들 수 있도록 먼저 색인을 ctx 에 넣는다
    def prepare(brand_data, ctx)
      by_name = {}
      brand_data['brands'].each { |b| by_name[b['name']] = b }
      bx_keys = {}
      brand_data['bxsg'].each { |x| bx_keys[[x['brand'], x['do'], x['sg']]] = x }
      ctx[:brand_names] = by_name
      ctx[:bx_keys] = bx_keys
    end

    # 반환: 검색 색인에 넣을 항목 배열
    def generate(site, brand_data, ctx, counts)
      brands = brand_data['brands']
      bxsg = brand_data['bxsg']
      by_name = ctx[:brand_names]
      bx_by_sgcat = Hash.new { |h, k| h[k] = [] }
      bxsg.each { |x| bx_by_sgcat[[x['do'], x['sg'], by_name[x['brand']]['cat']]] << x }
      by_cat = brands.group_by { |b| b['cat'] }

      brands.each do |b|
        rivals = (by_cat[b['cat']] || []).reject { |x| x['name'] == b['name'] }.sort_by { |x| -x['n'] }.first(10)
        site.pages << BrandPage.new(site, b, rivals, by_cat[b['cat']].sort_by { |x| -x['n'] }.index { |x| x['name'] == b['name'] }.to_i + 1, ctx)
        counts[:brand] += 1
      end
      bxsg.each do |x|
        b = by_name[x['brand']]
        rivals = bx_by_sgcat[[x['do'], x['sg'], b['cat']]].reject { |y| y['brand'] == x['brand'] }.sort_by { |y| -y['n'] }.first(8)
        site.pages << BrandSgPage.new(site, x, b, rivals, ctx)
        counts[:brandsg] += 1
      end
      site.pages << BrandIndexPage.new(site, brands, by_cat, ctx)
      brands.map { |b| { 'n' => b['name'], 't' => '브랜드', 'l' => "#{b['cat']} · 전국 #{SText.fmt(b['n'])}곳", 'u' => "/brand/#{SText.slug(b['name'])}/" } }
    end

    def brand_url(ctx, brand, do_short = nil, sg = nil)
      if do_short && ctx[:bx_keys][[brand, do_short, sg]]
        "/brand/#{SText.slug(brand)}/#{do_short}/#{sg}/"
      else
        "/brand/#{SText.slug(brand)}/"
      end
    end

    def rows(list, ctx, do_short, sg)
      list.map { |b, c| { 'name' => b, 'n' => SText.fmt(c), 'url' => brand_url(ctx, b, do_short, sg), 'cat' => ctx[:brand_names][b] ? ctx[:brand_names][b]['cat'] : '' } }
    end
  end

  class BrandPage < SBasePage
    def initialize(site, b, rivals, rank, ctx)
      setup(site, "brand/#{SText.slug(b['name'])}", 'brand')
      name = b['name']
      cat = b['cat']
      cat_total = ctx[:nat_sml_n][cat]
      data['bName'] = name
      data['cat'] = cat
      data['catUrl'] = cat_total ? "/biz/#{SText.slug(cat)}/" : nil
      data['period'] = ctx[:period]
      data['n'] = f(b['n'])
      data['nsg'] = b['nsg']
      data['rank'] = rank
      data['catShare'] = cat_total ? SText.pct(b['n'], cat_total) : nil
      data['perSg'] = format('%.1f', b['n'].to_f / b['nsg'])
      data['doRows'] = b['do'].map { |d, c| { 'name' => d, 'n' => f(c), 'share' => SText.pct(c, b['n']), 'w' => [(c.to_f / b['n'] * 100 * 2).round, 100].min } }
      data['sgRows'] = b['sgTop'].map do |d, g, c|
        { 'name' => "#{d} #{g}", 'n' => f(c), 'url' => SbizBrand.brand_url(ctx, name, d, g), 'sgUrl' => "/sg/#{d}/#{g}/" }
      end
      data['dongRows'] = b['dongTop'].map do |d, g, dn, c|
        dk = ctx[:dong_keys][[d, g, dn]]
        { 'name' => "#{g} #{dn}", 'n' => f(c), 'url' => dk ? "/dong/#{d}/#{g}/#{dn}/" : nil }
      end
      data['rivals'] = rivals.map { |x| { 'name' => x['name'], 'n' => f(x['n']), 'url' => "/brand/#{SText.slug(x['name'])}/", 'share' => cat_total ? SText.pct(x['n'], cat_total) : '-' } }
      top_do = b['do'].first
      top_sg = b['sgTop'].first
      s = +"#{SText.eun_neun(name)} #{ctx[:period]} 기준 전국 #{b['nsg']}개 시군구에 #{f(b['n'])}곳의 매장이 집계되는 #{cat} 브랜드입니다(같은 업종 브랜드 중 #{rank}위"
      s << ", #{cat} 전체 점포의 #{data['catShare']}" if data['catShare']
      s << "). "
      s << "시도별로는 #{top_do[0]}에 #{f(top_do[1])}곳으로 가장 많고, " if top_do
      s << "시군구로는 #{top_sg[0]} #{top_sg[1]}에 #{f(top_sg[2])}곳이 있습니다." if top_sg
      data['summary'] = s
      seo("#{name} 매장 수·지역별 지점 현황 #{ctx[:period][0, 4]}", "#{name} 전국 #{f(b['n'])}곳. 시도·시군구·동네별 매장 수와 같은 업종 브랜드 비교(#{cat}). 소상공인 상가업소 자료 기준.")
      faq([["#{name} 매장은 전국에 몇 곳인가요?", "#{ctx[:period]} 기준 소상공인시장진흥공단 상가업소 자료에서 #{f(b['n'])}곳이 집계됩니다. 상호명으로 브랜드를 식별한 값이라 실제 가맹본부 공시 수치와 다를 수 있습니다."],
           ["#{name} 매장이 가장 많은 지역은 어디인가요?", top_sg ? "시군구 기준으로 #{top_sg[0]} #{top_sg[1]}에 #{f(top_sg[2])}곳이 있어 가장 많습니다." : '집계된 지역이 없습니다.'],
           ['매장 수가 실제와 다를 수 있는 이유는 무엇인가요?', '공단 자료는 분기 단위 조사라 최근 개점·폐점이 빠질 수 있고, 일부 직영점이나 입점 매장은 상호가 달라 집계되지 않을 수 있습니다. 정확한 지점 정보는 브랜드 공식 사이트에서 확인하세요.']])
    end
  end

  class BrandSgPage < SBasePage
    def initialize(site, x, b, rivals, ctx)
      setup(site, "brand/#{SText.slug(b['name'])}/#{x['do']}/#{x['sg']}", 'brandsg')
      name = b['name']
      cat = b['cat']
      place = "#{x['do']} #{x['sg']}"
      cat_n = (ctx[:biz_keys][[x['do'], x['sg'], cat]] || {})['n']
      sg = ctx[:sg_idx][[x['do'], x['sg']]]
      data['bName'] = name
      data['place'] = place
      data['doShort'] = x['do']
      data['sigungu'] = x['sg']
      data['cat'] = cat
      data['period'] = ctx[:period]
      data['n'] = f(x['n'])
      data['catN'] = cat_n ? f(cat_n) : nil
      data['catShare'] = cat_n ? SText.pct(x['n'], cat_n) : nil
      data['sgN'] = f(sg['n'])
      data['natAvg'] = format('%.1f', b['n'].to_f / b['nsg'])
      data['dongRows'] = x['dongs'].map do |dn, c|
        dk = ctx[:dong_keys][[x['do'], x['sg'], dn]]
        { 'name' => dn, 'n' => f(c), 'share' => SText.pct(c, x['n']), 'w' => [(c.to_f / x['n'] * 100).round, 100].min, 'url' => dk ? "/dong/#{x['do']}/#{x['sg']}/#{dn}/" : nil }
      end
      data['rivals'] = rivals.map { |y| { 'name' => y['brand'], 'n' => f(y['n']), 'url' => "/brand/#{SText.slug(y['brand'])}/#{y['do']}/#{y['sg']}/", 'share' => cat_n ? SText.pct(y['n'], cat_n) : '-' } }
      data['natUrl'] = "/brand/#{SText.slug(name)}/"
      data['catUrl'] = ctx[:biz_keys][[x['do'], x['sg'], cat]] ? "/biz/#{SText.slug(cat)}/#{x['do']}/#{x['sg']}/" : nil
      data['sgUrl'] = "/sg/#{x['do']}/#{x['sg']}/"
      top1 = x['dongs'].first
      s = +"#{place}에는 #{ctx[:period]} 기준 #{name} 매장이 #{f(x['n'])}곳 집계됩니다"
      s << "(#{x['sg']}의 #{cat} #{f(cat_n)}곳 중 #{data['catShare']})" if cat_n
      s << ". 전국 시군구 평균(#{data['natAvg']}곳)과 비교하면 #{x['n'] >= b['n'].to_f / b['nsg'] ? '많은' : '적은'} 편입니다. "
      s << "#{top1[0]}에 #{f(top1[1])}곳으로 가장 많이 몰려 있습니다." if top1
      data['summary'] = s
      seo("#{place} #{name} 매장 현황 - #{f(x['n'])}곳·동네별 분포 #{ctx[:period][0, 4]}", "#{place} #{name} #{f(x['n'])}곳. 동네별 매장 수와 같은 지역 #{cat} 경쟁 브랜드 비교. 소상공인 상가업소 자료 기준.")
      faq([["#{place}에는 #{name} 매장이 몇 곳 있나요?", "#{ctx[:period]} 기준 #{f(x['n'])}곳이 집계됩니다. 조사 이후 개점·폐점은 반영되지 않을 수 있습니다."],
           ["#{name} 매장이 가장 많은 동네는 어디인가요?", top1 ? "#{top1[0]}에 #{f(top1[1])}곳이 있어 가장 많습니다." : '집계된 동네가 없습니다.']])
    end
  end

  class BrandIndexPage < SBasePage
    def initialize(site, brands, by_cat, ctx)
      setup(site, 'brand', 'brandindex')
      data['period'] = ctx[:period]
      data['total'] = f(brands.sum { |b| b['n'] })
      data['cats'] = by_cat.map do |cat, list|
        cat_total = ctx[:nat_sml_n][cat]
        { 'name' => cat, 'n' => list.sum { |b| b['n'] }, 'brands' => list.sort_by { |b| -b['n'] }.map { |b| { 'name' => b['name'], 'n' => f(b['n']), 'url' => "/brand/#{SText.slug(b['name'])}/", 'share' => cat_total ? SText.pct(b['n'], cat_total) : '-' } } }
      end.sort_by { |c| -c['n'] }.each { |c| c['n'] = f(c['n']) }
      seo("프랜차이즈 브랜드별 매장 수 - 편의점·카페·치킨 지점 현황 #{ctx[:period][0, 4]}", "CU·GS25·스타벅스·메가커피·BBQ 등 #{brands.size}개 프랜차이즈 브랜드의 전국·지역별 매장 수와 업종 내 점유율. 소상공인 상가업소 자료 기준.")
    end
  end
end
