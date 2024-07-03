--------------------------------------------------------------------------------
-- inject utf8 functions to strings
--------------------------------------------------------------------------------

string.ubyte = utf8extra.byte
string.uchar = utf8extra.char
string.ufind = utf8extra.find
string.ugmatch = utf8extra.gmatch
string.ugsub = utf8extra.gsub
string.ulen = utf8extra.len
string.ulower = utf8extra.lower
string.umatch = utf8extra.match
string.ureverse = utf8extra.reverse
string.usub = utf8extra.sub
string.uupper = utf8extra.upper

string.uescape = utf8extra.escape
string.ucharpos = utf8extra.charpos
string.unext = utf8extra.next
string.uinsert = utf8extra.insert
string.uremove = utf8extra.remove
string.uwidth = utf8extra.width
string.uwidthindex = utf8extra.widthindex
string.utitle = utf8extra.title
string.ufold = utf8extra.fold
string.uncasecmp = utf8extra.ncasecmp
string.uisvalid = utf8extra.isvalid
string.uclean = utf8extra.clean
string.uinvalidoffset = utf8extra.invalidoffset
string.uisnfc = utf8extra.isnfc
string.unormalize_nfc = utf8extra.normalize_nfc

string.uoffset = utf8extra.offset
string.ucodepoint = utf8extra.codepoint
string.ucodes = utf8extra.codes

--------------------------------------------------------------------------------
-- Inject utf8 module to lua < 5.3
--------------------------------------------------------------------------------

if not utf8 then
  utf8 = {
    charpattern = utf8extra.charpattern,
    char = utf8extra.char,
    codes = utf8extra.codes,
    codepoint = utf8extra.codepoint,
    len = utf8extra.len,
    offset = utf8extra.offset
  }
end
