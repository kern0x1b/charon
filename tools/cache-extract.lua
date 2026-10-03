-- xmake lua tools/cache-extract.lua <modules> <cachefile> <install> <outputfile>
--
-- One image out of a dyld shared cache, written where tools/cfconst/cache32.py can read it: that reader
-- walks an extracted image's own symbol table and takes no cache at all, which is what an image of 32
-- bits needs - its pointers are 32 bits wide and carry no flags above an address, so the 64-bit reader
-- (tools/cfconst.py) refuses it by name and names this route instead.
--
-- The extraction is dyld.lua's own extract() and not a second reading of the format: it rebuilds the
-- load commands, lays the segments out again and applies the rebase opcodes, and tools/cfconst.py says
-- in as many words that this is the way to get at an image it cannot read in place.
--
-- <modules> is the repository's modules/ directory, because the extraction is that tree's code and
-- nothing else carries it. `xmake firmware extract --library=INSTALL --output=FILE` is the same walk
-- through the build system and needs the firmware-tools package installed; this needs nothing but the
-- checkout it is run from.
function main(modules, cachefile, install, outputfile)
    local dyld = import("apple.dyld", {rootdir = modules, anonymous = true})
    local taken = dyld.extract(cachefile, install, outputfile)
    -- The one number a caller can check: extract() writes the file itself, so a run that raised before
    -- the write leaves no image and a caller that went on to read one would be reading nothing.
    local handle = io.open(outputfile, "rb")
    if not handle then
        raise("extract() reported " .. tostring(taken.symbols) .. " symbols but wrote no " .. outputfile)
    end
    local size = handle:seek("end")
    handle:close()
    if size == 0 then
        raise("extract() wrote an empty " .. outputfile)
    end
    print("extracted " .. install .. ": " .. tostring(#taken.segments) .. " segments, "
          .. tostring(taken.symbols) .. " symbols, " .. tostring(math.tointeger(size)) .. " bytes")
end