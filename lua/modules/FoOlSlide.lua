local dirurl           = '/directory/'
local dirurlreader     = '/reader/directory/'
local dirurlfoolslide  = '/foolslide/directory/'
local dirurlslide      = '/slide/directory/'
local dirurlslideU     = '/Slide/directory/'
local dirurlonline     = '/online/directory/'
local dirurlhelvetica  = '/r/directory/'
local dirurllector     = '/lector/directory/'
local dirurlfsdir      = '/fs/directory/'
local dirurlreaderlist = '/fs/reader/list/'

function getWithCookie(lurl)
  if HTTP.GET(lurl) then
    local x = TXQuery.Create(HTTP.Document)
    local s = x.XPathString('//form//input[(@type="hidden") and (@name="adult")]/@value')
    if s:lower() == 'true' then
      HTTP.Reset()
      return HTTP.POST(lurl, 'adult=true')
    end
    return true
  else
    return false
  end
end

function getdirurl(website)
  local dirs  = {
    ['Jaiminisbox']        = dirurlreader,
    ['DokiFansubs']        = dirurlreader,
    ['OneTimeScans']       = dirurl,
    ['DejameProbar']       = dirurlslide,
    ['MenudoFansub']       = dirurlslide,
    ['SolitarioNoFansub']  = dirurlslide,
    ['Pzykosis666HFansub'] = dirurlonline,
    ['SeinagiFansub']      = dirurlonline,
    ['HelveticaScans']     = dirurlhelvetica,
    ['RavensScans']        = dirurllector,
    ['NoraNoFansub']       = dirurllector,
    ['AntisenseScans']     = dirurlonline,
	['SenseScans']         = dirurlreader,
    ['MangaichiScan']      = dirurlfsdir,
    ['Riceballicious']     = dirurlreaderlist,
    ['Yuri-ism']           = dirurlslide,
    ['MangajinNoFansub']   = dirurllector,
    ['BunnysScans']        = '/read/directory/',
    ['CanisMajorScans']    = dirurlreader,
    ['HoshikuzuuScans']    = dirurl,
    ['YaoiIsLife']         = dirurlreader,
    ['FujoshiBitches']     = dirurlreader,
    ['TapTrans']           = dirurlfsdir,
    ['LoliVault']          = dirurlonline,
    ['Shoujohearts']       = dirurlreader
  }
  if dirs[website] ~= nil then
    return dirs[website]
  else
    return dirurl
  end
end

function getinfo()
  local lurl = MaybeFillHost(MODULE.RootURL, URL)
  local result = net_problem
  if getWithCookie(lurl) then
    x = TXQuery.Create(HTTP.Document)
    MANGAINFO.CoverLink = x.XPathString('//div[@class="thumbnail" or contains(@class, "thumb")]/img/@src')
    if MANGAINFO.Title == '' then
      MANGAINFO.Title = x.XPathString('//h1[@class="title"]')
    end
    if Pos('emailprotected', MANGAINFO.Title) > 0 then
      MANGAINFO.Title = Trim(SeparateLeft(x.XPathString('//title'), '::'))
    end
    local cls = 'info'
    MANGAINFO.Authors = string.gsub(x.XPathString('//div[@class="'..cls..'"]/*[contains(text(),"Author")]/following-sibling::text()[1]'), '^[%s:]*', '')
    MANGAINFO.Artists = string.gsub(x.XPathString('//div[@class="'..cls..'"]/*[contains(text(),"Artist")]/following-sibling::text()[1]'), '^[%s:]*', '')
    MANGAINFO.Summary = string.gsub(x.XPathString('//div[@class="'..cls..'"]/*[contains(text(),"Synopsis")]/following-sibling::text()[1]'), '^[%s:]*', '')
    v = x.XPath('//div[@class="list"]//div[@class="title"]/a')
    for i = 1, v.Count do
      v1 = v.Get(i)
      MANGAINFO.ChapterLinks.Add(v1.GetAttribute('href'))
      if v1.GetAttribute('title') ~= '' then
        MANGAINFO.ChapterNames.Add(v1.GetAttribute('title'))
      else
        MANGAINFO.ChapterNames.Add(v1.ToString())
      end
    end
    InvertStrings(MANGAINFO.ChapterLinks, MANGAINFO.ChapterNames)
    result = no_error
  end
  return result
end

function getinfo_ths()
  MANGAINFO.URL = MaybeFillHost(MODULE.RootURL, URL)
  if getWithCookie(MANGAINFO.URL) then
    local x = TXQuery.Create(HTTP.Document)
    MANGAINFO.Title     = x.XPathString('//div[@id="series_right"]/h1')
    MANGAINFO.CoverLink = MaybeFillHost(MODULE.RootURL, x.XPathString('//img[@class="series_img"]/@src'))
    MANGAINFO.Authors   = x.XPathString('//ul[@class="series_left_data"]/li[contains(span, "Author")]/span[@class="value"]')
    MANGAINFO.Artists   = x.XPathString('//ul[@class="series_left_data"]/li[contains(span, "Artist")]/span[@class="value"]')
    MANGAINFO.Genres    = x.XPathStringAll('//ul[@class="series_left_data"]/li[contains(span, "Genre")]/span[@class="value"]/text()')
    MANGAINFO.Status    = MangaInfoStatusIfPos(x.XPathString('//ul[@class="series_left_data"]/li[contains(span, "Status")]/span[@class="value"]'))
    MANGAINFO.Summary   = x.XPathString('//div[@id="series_des"]')
    x.XPathHREFTitleAll('//div[@id="staff"]/div/a', MANGAINFO.ChapterLinks, MANGAINFO.ChapterNames)
    InvertStrings(MANGAINFO.ChapterLinks,MANGAINFO.ChapterNames)
    return no_error
  else
    return net_problem
  end
end

function taskstart()
  TASK.PageLinks.Clear()
  TASK.PageNumber = 0
  return true
end

function getpagenumber()
  local result = false
  if getWithCookie(MaybeFillHost(MODULE.RootURL, URL)) then
    x = TXQuery.Create(HTTP.Document)
    TASK.PageNumber = x.XPath('//div[@class="topbar_right"]//ul[@class="dropdown"]/li').Count
    s = x.XPathString('//script[contains(.,"var pages")]')
    if s ~= '' then
      s = GetBetween('var pages = ', ';', s)
      if Pos('atob("', s) > 0 then
         s = GetBetween('atob("', '")', s)
         s = DecodeBase64(s)
      end
      x.ParseHTML(s)
      v = x.XPath('json(*)()("URL")')
      for i = 1, v.Count do
        TASK.PageLinks.Add(v.Get(i).ToString())
      end
    end
    result = true
  end
  return result
end

function getimageurl()
  local result = false
  local s = URL
  if WORKID > 0 then
    s = AppendURLDelim(s) .. 'page/' .. (WORKID + 1)
  end
  if getWithCookie(MaybeFillHost(MODULE.RootURL, s)) then
    x = TXQuery.Create(HTTP.Document)
    TASK.PageLinks.Set(WORKID, x.XPathString('//div[@id="page"]//img/@src'))
  end
  return result
end

function getdirectorypagenumber()
  local result = net_problem
  PAGENUMBER = 1
  if getWithCookie(MODULE.RootURL .. getdirurl(MODULE.Name)) then
    result = no_error
    x = TXQuery.Create(HTTP.Document)
    v = x.XPath('//*[@class="next"]/a/@href')
    for i = 1, v.Count do
      local s = tonumber(string.match(v.Get(i).ToString(), '/(%d+)/$'))
      if (s ~= nil) and (s > PAGENUMBER) then
        PAGENUMBER = s
      end
    end
  end
  return result
end

function getnameandlink()
  local result = net_problem
  local s = MODULE.RootURL .. getdirurl(MODULE.Name)
  if URL ~= '0' then
    s = s .. (tonumber(URL) + 1) .. '/'
  end
  if getWithCookie(s) then
    result = no_error
    local x = TXQuery.Create(HTTP.Document)
    if MODULE.Name == 'TwistedHelScans' then
      local v = x.XPath('//div[contains(@class, "series_card")]/a')
      for i = 1, v.Count do
        local v1 = v.Get(i)
        LINKS.Add(v1.GetAttribute('href'))
        NAMES.Add(x.XPathString('span', v1))
      end
    else
      x.XPathHREFAll('//div[@class="list series"]/div/div[@class="title"]/a', LINKS, NAMES)
    end
  end
  return result
end

function Init()
  function AddWebsiteModule(id, name, url, category)
    local m  = NewWebsiteModule()
    m.ID                       = id
    m.Name                     = name
    m.RootURL                  = url
    m.Category                 = category
    m.OnGetInfo                = 'getinfo'
    m.OnTaskStart              = 'taskstart'
    m.OnGetPageNumber          = 'getpagenumber'
    m.OnGetImageURL            = 'getimageurl'
    m.OnGetDirectoryPageNumber = 'getdirectorypagenumber'
    m.OnGetNameAndLink         = 'getnameandlink'
    return m
  end
  local cat = 'English-Scanlation'
  AddWebsiteModule('941d6b7dc1bf4ccd9032486f3d18664a', 'AntisenseScans', 'http://antisensescans.com', cat)
  AddWebsiteModule('25a93ecfc2c44cd6978b3083f8a4579c', 'BunnysScans', 'http://bns.shounen-ai.net', cat)
  AddWebsiteModule('9aae7e3f5a5e4aeda5bb840d8e08790f', 'CanisMajorScans', 'http://cm-scans.shounen-ai.net', cat)
  AddWebsiteModule('613368d384af4edf8036b869c85e2967', 'DeathTollScans', 'https://reader.deathtollscans.net', cat)
  AddWebsiteModule('6c342d65b72d48b3b2235fd342f4144a', 'DokiFansubs', 'https://kobato.hologfx.com', cat)
  AddWebsiteModule('d2de9fa802a74b59b018140c2236b440', 'EvilFlowers', 'http://reader.evilflowers.com', cat)
  AddWebsiteModule('b1239d37a3df41cbb915149f63afaa2d', 'ForgottenScans', 'http://reader.fos-scans.com', cat)
  AddWebsiteModule('f2f619f61e104881aeccffa3ece0e853', 'FujoshiBitches', 'http://fujoshibitches.shounen-ai.net', cat)
  AddWebsiteModule('fc71889917094f61940ee7a9222a73bc', 'HelveticaScans', 'http://helveticascans.com', cat)
  AddWebsiteModule('ed2fa3be6e104af48ec4e40dbff91708', 'HoshikuzuuScans', 'http://hoshiscans.shounen-ai.net', cat)
  AddWebsiteModule('18c40b09aaa14c1ba9d8bd62848667d6', 'IlluminatiManga', 'http://reader.manga-download.org', cat)
  AddWebsiteModule('8819a794f9d342bca505c8954bf4e414', 'Jaiminisbox', 'https://jaiminisbox.com', cat)
  AddWebsiteModule('02c7122dc41b448da60a40a9f6394fd6', 'KireiCake', 'https://reader.kireicake.com', cat)
  AddWebsiteModule('646d143d779649c6b567d5822c836c81', 'MangaichiScan', 'http://mangaichiscans.mokkori.fr', cat)
  AddWebsiteModule('56d58cc4a4624f39a327a4ddf26a3594', 'OneTimeScans', 'https://reader.otscans.com', cat)
  AddWebsiteModule('6b599fa5bf774a3d91d7144a734de08e', 'PhoenixSerenade', 'https://reader.serenade.moe', cat)
  AddWebsiteModule('2a01ac2aacdb4649b9935bf0bf9ab1b1', 'PowerManga', 'http://read.powermanga.org', cat)
  AddWebsiteModule('619fb02297f240bbbf9642689a9a5462', 'Riceballicious', 'http://riceballicious.info', cat)
  AddWebsiteModule('d96af7be590b4fa4a3dd2107a1b0ee96', 'RoseliaScanlations', 'http://reader.roseliascans.com', cat)
  AddWebsiteModule('bf6389bd91f442a3a92ca93441e2e1da', 'S2Scans', 'https://reader.s2smanga.com', cat)
  AddWebsiteModule('52618a96ca2a4715b1713ca861435263', 'SeaOtterScans', 'https://reader.seaotterscans.com', cat)
  AddWebsiteModule('2d2a00be15ab4c6195d3a10f17fa73da', 'SenseScans', 'http://sensescans.com', cat)
  AddWebsiteModule('aa03dca926834667a5691c4592c70b4c', 'Shoujohearts', 'http://shoujohearts.com', cat)
  AddWebsiteModule('8fe7f19214a5401ba293f7ecb6afe398', 'Shoujosense', 'http://reader.shoujosense.com', cat)
  AddWebsiteModule('ca6c3ca43aba4420b064615296e6d550', 'SilentSkyScans', 'http://reader.silentsky-scans.net', cat)
  AddWebsiteModule('9dd75e6aa4e944f7ba955af7057acd8d', 'TapTrans', 'https://taptaptaptaptap.net', cat)
  AddWebsiteModule('a309ceeaf25c4c5dbbfedb65678bf14c', 'TheCatScans', 'https://reader2.thecatscans.com', cat)
  AddWebsiteModule('6fbd8012ff3d4a97829dd91bfee95d3e', 'TwistedHelScans', 'http://www.twistedhelscans.com', cat).OnGetInfo = 'getinfo_ths'
  AddWebsiteModule('e1bb1dd018ff498382dba79d28c401d5', 'VortexScans', 'https://reader.vortex-scans.com', cat)
  AddWebsiteModule('b12d310a4bdc4f368a489b8187233f62', 'WorldThree', 'http://www.slide.world-three.org', cat)
  AddWebsiteModule('fb8447279932432fb68f5cad6a6a12b3', 'YaoiIsLife', 'http://yaoislife.shounen-ai.net', cat)
  AddWebsiteModule('fb47357ef4cc4c8992999841949ef7d1', 'Yuri-ism', 'https://www.yuri-ism.net', cat)

  -- es-sc
  cat = 'Spanish-Scanlation'
  AddWebsiteModule('639c7f8e27f74314ad9b474460086384', 'KirishimaFansub', 'http://lector.kirishimafansub.net', cat)
  AddWebsiteModule('218b722b1eb34f2aa3863f84538c5b08', 'LoliVault', 'https://lolivault.net', cat)
  AddWebsiteModule('1e3d6dac50344396b8267da9a885ac05', 'Mangasubes', 'http://mangasubes.patyscans.com', cat)
  AddWebsiteModule('ba071f02443e40a3805d32c62169afb4', 'MenudoFansub', 'http://www.menudo-fansub.com', cat)
  AddWebsiteModule('3c2b3506180a494fb0ee1ac880812577', 'NeoProjectScan', 'http://npscan.mangaea.net', cat)
  AddWebsiteModule('9d67e57014254506a352018e43a8115d', 'Nightow', 'http://nightow.net', cat)
  AddWebsiteModule('c3848692b2d9422b9ecc49c7c616fd3a', 'NoraNoFansub', 'https://www.noranofansub.com', cat)
  AddWebsiteModule('3884c90f93f94d4f91139d344d465f48', 'PCNet', 'http://pcnet.patyscans.com', cat)
  AddWebsiteModule('1df9cf8bde734241b6daed49616e4181', 'PatyScans', 'http://lector.patyscans.com', cat)
  AddWebsiteModule('0f7a8fd035ed4598812ecb2c6da57569', 'Pzykosis666HFansub', 'https://pzykosis666hfansub.com', cat)
  AddWebsiteModule('b813305c4ade47ab938578ac54f098cc', 'RavensScans', 'http://ravens-scans.com', cat)
  AddWebsiteModule('5c934d0556d44e0ba057eb7778a0cda4', 'SeinagiAdultoFansub', 'https://adulto.seinagi.org.es', cat)
  AddWebsiteModule('4c5e7c7582f6402b9bab2b019c8c4429', 'SeinagiFansub', 'https://seinagi.org.es', cat)
  AddWebsiteModule('08676da7a7284009b893e07e46f86b2e', 'SolitarioNoFansub', 'http://snf.mangaea.net', cat)
  AddWebsiteModule('92573b6b9b8743989709980fb6ddaf43', 'TrueColorsScan', 'https://truecolorsscans.miocio.org', cat)
  AddWebsiteModule('912545e52513414cabdc006260bcef6d', 'XAnimeSeduccion', 'http://xanime-seduccion.com', cat)
end
