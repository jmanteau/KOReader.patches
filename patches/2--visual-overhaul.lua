--[[ Visual overhaul: stretched rounded covers, folder covers, series badges,
     progress bars, percent badges, pages badges, dogear icons, virtual series folders.
     Merges: 2--covers.lua, 2-cover-overlays.lua, 2-automatic-book-series.lua ]]
--

local ok, err = pcall(function()

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local IconWidget = require("ui/widget/iconwidget")
local userpatch = require("userpatch")
local util = require("util")

local _ = require("gettext")
local Screen = Device.screen
local logger = require("logger")

--========================== [[Debug]] ==================================================
local DEBUG_ICONS = false  -- set false to silence custom-icon diagnostics
--=======================================================================================

--========================== [[Feature toggles]] ==========================================
-- Set to false to disable a feature. These are defaults; toggle at runtime
-- via Menu > File browser > Mosaic and detailed list settings > Visual features.
local cfg_features = {
    cover_aspect_ratio = true,   -- Stretched covers with custom aspect ratio
    rounded_corners    = true,   -- Rounded corner overlays on covers
    folder_covers      = true,   -- Show cover images on folders
    stacked_bars       = true,   -- Stacked bars above folder covers
    title_strip        = true,   -- Book title + author below cover
    progress_bar       = true,   -- Reading progress bar on covers
    percent_badge      = true,   -- Percentage read badge (top-right)
    pages_badge        = true,   -- Page count badge (bottom-left)
    series_badge       = true,   -- Series index "#N" badge (top-center)
    dogear             = true,   -- Status dogear icons (reading/complete/abandoned)
    new_badge          = true,   -- "New" badge on recently added unread books
    virtual_series     = true,   -- Auto-group books by series into virtual folders
    image_as_cover     = true,   -- Use same-basename images as book covers
    wallpaper_mode     = false,  -- Transparent backgrounds for wallpaper compatibility
}
--=========================================================================================

--========================== [[Cover preferences]] ======================================
local aspect_ratio = 2 / 3          -- adjust aspect ratio of folder cover
local stretch_limit = 50            -- adjust the stretching limit
local fill = false                  -- set true to fill the entire cell ignoring aspect ratio
local file_count_size = 14          -- font size of the file count badge
local folder_font_size = 20         -- font size of the folder name
local folder_border = 0.5           -- thickness of folder border
local folder_name = true            -- set to false to remove folder title from the center
--======================================================================================

--========================== [[Pages badge preferences]] ================================
local pages_cfg = {
    font_size = 10,                               -- Direct font size (passed to Font:getFace)
    text_color = Blitbuffer.COLOR_WHITE,          -- Choose your desired color
    border_thickness = 2,                         -- Adjust from 0 to 5
    border_corner_radius = 12,                    -- Adjust from 0 to 20
    border_color = Blitbuffer.COLOR_DARK_GRAY,    -- Choose your desired color
    background_color = Blitbuffer.COLOR_GRAY_3,   -- Choose your desired color
    inset_x = Screen:scaleBySize(4),              -- Horizontal inset from cover edge
    inset_y = Screen:scaleBySize(8),              -- Vertical inset from cover edge
}

--========================== [[Percent badge preferences]] ==============================
local percent_cfg = {
    text_size = 14,     -- Direct font size (passed to Font:getFace)
    move_on_x = -15,     -- Adjust how far left the badge should sit
    move_on_y = -1,     -- Adjust how far up the badge should sit
    badge_w = 70,       -- Adjust badge width
    badge_h = 40,       -- Adjust badge height
    bump_up = 1,        -- Adjust text position
}

--========================== [[Series badge preferences]] ===============================
local series_cfg = {
    font_size = 11,                                          -- Adjust from 0 to 1
    border_thickness = 1,                                    -- Adjust from 0 to 5
    border_corner_radius = 9,                                -- Adjust from 0 to 20
    text_color = Blitbuffer.colorFromString("#000000"),      -- Choose your desired color
    border_color = Blitbuffer.colorFromString("#000000"),    -- Choose your desired color
    background_color = Blitbuffer.COLOR_GRAY_E,              -- Choose your desired color
}

--========================== [[Title strip preferences]] ==================================
local title_cfg = {
    font_size = 14,
    meta_font_size = 12,
    max_lines = 3,
    padding = 4,
    text_color = Blitbuffer.COLOR_BLACK,
    meta_color = Blitbuffer.COLOR_DARK_GRAY,
    card_gap = 10,
}

--========================== [[Focus border preferences]] =================================
local focus_cfg = {
    border_width = 12,
    color = Blitbuffer.COLOR_BLACK,
}

--========================== [[Progress bar preferences]] ===============================
local bar_cfg = {
    H = Screen:scaleBySize(9),                              -- bar height
    RADIUS = Screen:scaleBySize(3),                         -- rounded ends
    PERCENT_POS = 77 / 100,                                   -- vertical position as fraction of cover height
    TRACK_COLOR = Blitbuffer.colorFromString("#F4F0EC"),     -- bar color
    FILL_COLOR = Blitbuffer.colorFromString("#555555"),      -- fill color
    ABANDONED_COLOR = Blitbuffer.colorFromString("#C0C0C0"), -- fill when abandoned/paused
    BORDER_W = Screen:scaleBySize(0.5),                     -- border width around track (0 to disable)
    BORDER_COLOR = Blitbuffer.COLOR_BLACK,                   -- border color
    MIN_PERCENT = 0.02,                                     -- hide bar below this (2%)
    NEAR_COMPLETE_PERCENT = 0.97,                           -- treat as complete above this (97%)
}
--=======================================================================================

local FolderCover = {
    name = ".cover",
    exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
}

-- ============================================================================
-- Hide images that share a basename with a book file; use them as covers
-- ============================================================================
local image_ext_set = {}
for _, ext in ipairs(FolderCover.exts) do
    image_ext_set[ext:sub(2):lower()] = true  -- strip leading dot
end

local function filterMatchingImages(item_table)
    if not item_table then return end

    local book_basenames = {}
    for _, item in ipairs(item_table) do
        if item.is_file and item.path then
            local base, suffix = util.splitFileNameSuffix(item.path)
            if not image_ext_set[suffix:lower()] then
                book_basenames[base] = true
            end
        end
    end

    local i = 1
    while i <= #item_table do
        local item = item_table[i]
        if item.is_file and item.path then
            local base, suffix = util.splitFileNameSuffix(item.path)
            if image_ext_set[suffix:lower()] and book_basenames[base] then
                table.remove(item_table, i)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

local Folder = {
    face = {
        border_size = 1,
        alpha = 0.75,
        nb_items_font_size = file_count_size,
        nb_items_margin = Screen:scaleBySize(5),
        dir_max_font_size = folder_font_size,
    },
}

--========================== [[New badge preferences]] ================================
local new_badge_cfg = {
    max_age_days = 30,
    badge_w = 55,
    badge_h = 30,
    inset_x = -10,
    inset_y = 2,
}

-- ============================================================================
-- Custom icon directories
-- ============================================================================
do
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")

    local dbg = DEBUG_ICONS and logger.info or function() end

    local icons_dirs = userpatch.getUpValue(IconWidget.init, "ICONS_DIRS")
    local icons_path = userpatch.getUpValue(IconWidget.init, "ICONS_PATH")

    dbg("[custom-icons] getDataDir():", DataStorage:getDataDir())
    dbg("[custom-icons] getFullDataDir():", tostring(DataStorage:getFullDataDir()))
    dbg("[custom-icons] lfs.currentdir():", lfs.currentdir())
    dbg("[custom-icons] icons_dirs upvalue:", icons_dirs and ("table, #" .. #icons_dirs) or "nil")
    dbg("[custom-icons] icons_path upvalue:", icons_path and "table" or "nil")

    if icons_dirs then
        dbg("[custom-icons] Original ICONS_DIRS:")
        for i, d in ipairs(icons_dirs) do
            dbg("[custom-icons]   [" .. i .. "]", d)
        end

        local data_dir = DataStorage:getFullDataDir()
        if not data_dir then
            logger.warn("[custom-icons] getFullDataDir() returned nil, falling back to getDataDir()")
            data_dir = DataStorage:getDataDir()
        end
        local variant_subdir = Device:hasColorScreen() and "icons-colours" or "icons-bw"
        local variant_dir = data_dir .. "/icons/" .. variant_subdir
        local all_dir     = data_dir .. "/icons/all"

        dbg("[custom-icons] hasColorScreen:", tostring(Device:hasColorScreen()))
        dbg("[custom-icons] variant_dir:", variant_dir)
        dbg("[custom-icons] all_dir:", all_dir)

        local all_mode = lfs.attributes(all_dir, "mode")
        dbg("[custom-icons] lfs.attributes(all_dir):", tostring(all_mode))
        if all_mode == "directory" then
            table.insert(icons_dirs, 1, all_dir)
        end

        local variant_mode = lfs.attributes(variant_dir, "mode")
        dbg("[custom-icons] lfs.attributes(variant_dir):", tostring(variant_mode))
        if variant_mode == "directory" then
            table.insert(icons_dirs, 1, variant_dir)
        end

        -- Clear cached icon paths so lookups use the new directories.
        if icons_path then
            local cleared = 0
            for k in pairs(icons_path) do
                icons_path[k] = nil
                cleared = cleared + 1
            end
            dbg("[custom-icons] Cleared", cleared, "cached icon paths")
        end

        dbg("[custom-icons] Final ICONS_DIRS:")
        for i, d in ipairs(icons_dirs) do
            dbg("[custom-icons]   [" .. i .. "]", d)
        end
    else
        logger.warn("[custom-icons] Could not get ICONS_DIRS upvalue from IconWidget.init")
    end
end

local function svg_widget(icon)
    local widget = IconWidget:new{ icon = icon, alpha = true }
    if DEBUG_ICONS then
        logger.info("[custom-icons] svg_widget('" .. icon .. "') -> file:", widget and widget.file or "nil")
    end
    return widget
end

local icons = { tl = "rounded.corner.tl", tr = "rounded.corner.tr", bl = "rounded.corner.bl", br = "rounded.corner.br" }
local corners = {}
for k, name in pairs(icons) do
    corners[k] = svg_widget(name)
    if not corners[k] then
        logger.warn("Failed to load SVG icon: " .. tostring(name))
    end
end

local CORNER_R
do
    local function _csz(w)
        if w and w.getSize then return w:getSize().w end
        if w and w.getWidth then return w:getWidth() end
        return 0
    end
    CORNER_R = _csz(corners.tl)
end

local function findCover(dir_path)
    local path = dir_path .. "/" .. FolderCover.name
    for _, ext in ipairs(FolderCover.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then return fname end
    end
end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local function getMenuItem(menu, ...)
    local function findItem(sub_items, texts)
        local find = {}
        for _, text in ipairs(type(texts) == "table" and texts or { texts }) do
            find[text] = true
        end
        for _, item in ipairs(sub_items) do
            local text = item.text or (item.text_func and item.text_func())
            if text and find[text] then return item end
        end
    end

    local sub_items, item
    for _, texts in ipairs { ... } do
        sub_items = (item or menu).sub_item_table
        if not sub_items then return end
        item = findItem(sub_items, texts)
        if not item then return end
    end
    return item
end

local function toKey(...)
    local keys = {}
    for _, key in pairs { ... } do
        if type(key) == "table" then
            table.insert(keys, "table")
            for k, v in pairs(key) do
                table.insert(keys, tostring(k))
                table.insert(keys, tostring(v))
            end
        else
            table.insert(keys, tostring(key))
        end
    end
    return table.concat(keys, "")
end

local function paintCorners(bb, x, y, w, h)
    local TL, TR, BL, BR = corners.tl, corners.tr, corners.bl, corners.br
    if not (TL and TR and BL and BR) then return end

    local function _sz(widget)
        if widget.getSize then
            local s = widget:getSize()
            return s.w, s.h
        end
        if widget.getWidth then
            return widget:getWidth(), widget:getHeight()
        end
        return 0, 0
    end

    local tlw, tlh = _sz(TL)
    local trw, trh = _sz(TR)
    local blw, blh = _sz(BL)
    local brw, brh = _sz(BR)

    if TL.paintTo then TL:paintTo(bb, x, y) else bb:blitFrom(TL, x, y) end
    if TR.paintTo then TR:paintTo(bb, x + w - trw, y) else bb:blitFrom(TR, x + w - trw, y) end
    if BL.paintTo then BL:paintTo(bb, x, y + h - blh) else bb:blitFrom(BL, x, y + h - blh) end
    if BR.paintTo then BR:paintTo(bb, x + w - brw, y + h - brh) else bb:blitFrom(BR, x + w - brw, y + h - brh) end
end

local function paintTopCorners(bb, x, y, w, h)
    local TL, TR = corners.tl, corners.tr
    if not (TL and TR) then return end
    local function _sz(widget)
        if widget.getSize then local s = widget:getSize(); return s.w, s.h end
        if widget.getWidth then return widget:getWidth(), widget:getHeight() end
        return 0, 0
    end
    local tlw, tlh = _sz(TL)
    local trw, trh = _sz(TR)
    if TL.paintTo then TL:paintTo(bb, x, y) else bb:blitFrom(TL, x, y) end
    if TR.paintTo then TR:paintTo(bb, x + w - trw, y) else bb:blitFrom(TR, x + w - trw, y) end
end

local function roundCornersFromBg(bb, strips, cell_x, cell_y, cell_h, fx, fy, fw, fh, r)
    local r2 = r * r
    for py = 0, r - 1 do
        for px = 0, r - 1 do
            local dx_tl, dy_tl = r - px, r - py
            if dx_tl * dx_tl + dy_tl * dy_tl > r2 then
                local sx = fx - cell_x + px
                bb:setPixel(fx + px, fy + py, strips.top:getPixel(sx, fy - cell_y + py))
            end
            local dx_tr = px
            if dx_tr * dx_tr + dy_tl * dy_tl > r2 then
                local cx = fw - r + px
                local sx = fx - cell_x + cx
                bb:setPixel(fx + cx, fy + py, strips.top:getPixel(sx, fy - cell_y + py))
            end
            local dy_bl = py
            if dx_tl * dx_tl + dy_bl * dy_bl > r2 then
                local cy = fh - r + py
                local sy = (fy + cy) - (cell_y + cell_h - r)
                local sx = fx - cell_x + px
                bb:setPixel(fx + px, fy + cy, strips.bot:getPixel(sx, sy))
            end
            if dx_tr * dx_tr + dy_bl * dy_bl > r2 then
                local cx = fw - r + px
                local cy = fh - r + py
                local sy = (fy + cy) - (cell_y + cell_h - r)
                local sx = fx - cell_x + cx
                bb:setPixel(fx + cx, fy + cy, strips.bot:getPixel(sx, sy))
            end
        end
    end
    strips.top:free()
    strips.bot:free()
end

local function getAspectRatioAdjustedDimensions(width, height, border_size)
    local available_w = width - 2 * border_size
    local available_h = height - 2 * border_size
    local ratio = fill and (available_w / available_h) or aspect_ratio

    local frame_w, frame_h
    if available_w / available_h > ratio then
        frame_h = available_h
        frame_w = available_h * ratio
    else
        frame_w = available_w
        frame_h = available_w / ratio
    end

    return { w = frame_w + 2 * border_size, h = frame_h + 2 * border_size }
end

local orig_FileChooser_getListItem = FileChooser.getListItem
local CACHE_MAX = 2000
local cached_list = {}
local cached_list_count = 0
function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
    if not cached_list[key] then
        if cached_list_count >= CACHE_MAX then
            cached_list = {}
            cached_list_count = 0
        end
        cached_list[key] = orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
        cached_list_count = cached_list_count + 1
    end
    return cached_list[key]
end

-- Icon constants for browser-up-folder compatibility
local Icon = {
    home = "home",
    up = BD.mirroredUILayout() and "back.top.rtl" or "back.top",
}

-- State for persisting virtual folder across refreshes
local current_series_group = nil

if not IconWidget.patched_new_status_icons then
    IconWidget.patched_new_status_icons = true

    local originalIconWidgetNew = IconWidget.new

    function IconWidget:new(o)
        local corner_icons = {
            "dogear.reading",
            "dogear.abandoned",
            "dogear.abandoned.rtl",
            "dogear.complete",
            "dogear.complete.rtl",
            "star.white",
        }

        for _, icon_name in ipairs(corner_icons) do
            if o.icon == icon_name then
                o.alpha = true
                break
            end
        end

        return originalIconWidgetNew(self, o)
    end
end

-- ============================================================================
-- Callback scope
-- ============================================================================

local function patchVisualOverhaul(plugin)
    local AlphaContainer = require("ui/widget/container/alphacontainer")
    local BookInfoManager = require("bookinfomanager")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local TitleBar = require("ui/widget/titlebar")
    local TopContainer = require("ui/widget/container/topcontainer")
    local lfs = require("libs/libkoreader-lfs")
    local VerticalSpan = require("ui/widget/verticalspan")
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem or MosaicMenuItem.patched_visual_overhaul then return end
    MosaicMenuItem.patched_visual_overhaul = true

    -- Feature toggle helpers (persisted via BookInfoManager, defaults from cfg_features)
    local FEAT_PREFIX = "feat_"
    local function feat(key)
        local stored = BookInfoManager:getSetting(FEAT_PREFIX .. key)
        if stored == nil then return cfg_features[key] ~= false end
        return stored == "Y"
    end
    local function toggleFeat(key)
        BookInfoManager:saveSetting(FEAT_PREFIX .. key, feat(key) and "N" or "Y")
    end

    -- [image_as_cover] Use same-basename images as book covers
    local DocSettings = require("docsettings")
    local orig_findCustomCoverFile = DocSettings.findCustomCoverFile
    function DocSettings:findCustomCoverFile(doc_path, ...)
        local result = orig_findCustomCoverFile(self, doc_path, ...)
        if result then return result end
        if not feat("image_as_cover") then return end

        doc_path = doc_path or (self.data and self.data.doc_path)
        if not doc_path then return end

        local base = util.splitFileNameSuffix(doc_path)
        for _, ext in ipairs(FolderCover.exts) do
            local img_path = base .. ext
            if util.fileExists(img_path) then
                return img_path
            end
        end
    end

    -- Compute title strip height (reused in init, update, paintTo)
    local title_face = Font:getFace("cfont", title_cfg.font_size)
    local _sample = TextWidget:new{ text = "Ag", face = title_face }
    local title_line_h = _sample:getSize().h
    _sample:free()
    local title_strip_h = title_line_h * title_cfg.max_lines + Screen:scaleBySize(title_cfg.padding)
    local card_gap_px = Screen:scaleBySize(title_cfg.card_gap)

    -- StretchingImageWidget + debug.setupvalue
    local max_img_w, max_img_h

    if not MosaicMenuItem.patched_aspect_ratio then
        MosaicMenuItem.patched_aspect_ratio = true

        local local_ImageWidget
        local n = 1
        while true do
            local name, value = debug.getupvalue(MosaicMenuItem.update, n)
            if not name then break end
            if name == "ImageWidget" then
                local_ImageWidget = value
                break
            end
            n = n + 1
        end

        if not local_ImageWidget then
            logger.warn("Could not find ImageWidget in MosaicMenuItem.update closure")
        else
            local StretchingImageWidget = local_ImageWidget:extend({})
            StretchingImageWidget.init = function(self)
                if local_ImageWidget.init then local_ImageWidget.init(self) end
                if not feat("cover_aspect_ratio") then return end
                if not max_img_w and not max_img_h then return end

                self.scale_factor = nil
                self.stretch_limit_percentage = stretch_limit

                local ratio = fill and (max_img_w / max_img_h) or aspect_ratio
                if max_img_w / max_img_h > ratio then
                    self.height = max_img_h
                    self.width = max_img_h * ratio
                else
                    self.width = max_img_w
                    self.height = max_img_w / ratio
                end
            end

            debug.setupvalue(MosaicMenuItem.update, n, StretchingImageWidget)
        end
    end

    -- Settings definitions
    local function BooleanSetting(text, name, default)
        local s = { text = text }
        s.get = function()
            local setting = BookInfoManager:getSetting(name)
            if default then return not setting end
            return setting
        end
        s.toggle = function() return BookInfoManager:toggleSetting(name) end
        return s
    end

    local settings = {
        name_centered = BooleanSetting(_("Folder name centered"), "folder_name_centered", true),
        show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", folder_name),
    }

    -- Capture originals before any overrides
    local orig_init = MosaicMenuItem.init
    local orig_paintTo = MosaicMenuItem.paintTo
    local orig_free = MosaicMenuItem.free
    local orig_update = MosaicMenuItem.update

    -- Corner mark size for progress bar (extract before wrapping paintTo)
    local corner_mark_size = userpatch.getUpValue(orig_paintTo, "corner_mark_size")
        or Screen:scaleBySize(24)

    -- Find upvalue index for corner_mark_size so we can suppress original corner marks
    local corner_mark_size_idx
    do
        local n = 1
        while true do
            local name = debug.getupvalue(orig_paintTo, n)
            if not name then break end
            if name == "corner_mark_size" then
                corner_mark_size_idx = n
                break
            end
            n = n + 1
        end
    end

    local function I(v)
        return math.floor(v + 0.5)
    end

    -- MosaicMenuItem.init -- ONE override
    function MosaicMenuItem:init()
        -- [covers] capture max_img_w/max_img_h
        if self.width and self.height then
            local border_size = Size.border.thin
            max_img_w = self.width - 2 * border_size
            if feat("title_strip") then
                max_img_h = self.height - 2 * border_size - title_strip_h - card_gap_px
            else
                max_img_h = self.height - 2 * border_size
            end
        end
        if orig_init then orig_init(self) end

        -- [overlays] build series badge
        if self.is_directory or self.file_deleted then return end

        if not feat("series_badge") then return end
        local bookinfo = BookInfoManager:getBookInfo(self.filepath, false)
        if bookinfo and bookinfo.series and bookinfo.series_index then
            self.series_index = bookinfo.series_index

            local series_text = TextWidget:new{
                text = "#" .. self.series_index,
                face = Font:getFace("cfont", series_cfg.font_size),
                bold = true,
                fgcolor = series_cfg.text_color,
            }

            self.series_badge = FrameContainer:new{
                linesize = Screen:scaleBySize(2),
                radius = Screen:scaleBySize(series_cfg.border_corner_radius),
                color = series_cfg.border_color,
                bordersize = series_cfg.border_thickness,
                background = series_cfg.background_color,
                padding = Screen:scaleBySize(2),
                margin = 0,
                series_text,
            }

            self._series_text = series_text
            self.has_series_badge = true
        end
    end

    -- MosaicMenuItem.update -- ONE override
    function MosaicMenuItem:update(...)
        orig_update(self, ...)

        -- [pages] Capture page count from sidecar (BookList cache, no new I/O)
        self.pages = nil
        if feat("pages_badge") and self.filepath and not self.is_directory and not self.file_deleted then
            local book_info = self.menu.getBookInfo(self.filepath)
            if book_info and book_info.pages then
                self.pages = book_info.pages
            end
        end

        -- [new] Flag recently added, unread books
        self._is_new = false
        if feat("new_badge") and self.filepath and not self.is_directory and not self.file_deleted
            and not self.percent_finished and not self.been_opened then
            local attr = lfs.attributes(self.filepath)
            if attr and attr.modification then
                local age_days = (os.time() - attr.modification) / 86400
                if age_days <= new_badge_cfg.max_age_days then
                    self._is_new = true
                end
            end
        end

        -- [title] Shrink CenterContainer so cover sits in top portion; store title/meta for paintTo
        if feat("title_strip") and self._has_cover_image and not self.is_directory and not self.file_deleted then
            local bookinfo = BookInfoManager:getBookInfo(self.filepath, false)
            local has_meta = bookinfo and not bookinfo.ignore_meta
            local title_text = (has_meta and bookinfo.title) or self.text
            if title_text then
                local existing = self._underline_container[1]  -- CenterContainer{FrameContainer{image}}
                if existing and existing.dimen then
                    existing.dimen.h = self.height - title_strip_h - card_gap_px
                end
                self._cover_frame = existing and existing[1]
                if self._cover_frame then
                    self._cover_frame.bordersize = 0
                end

                -- Build secondary line: series (#N) + author, or just author
                local meta_line
                if has_meta then
                    if bookinfo.series then
                        meta_line = bookinfo.series
                        if bookinfo.series_index then
                            meta_line = meta_line .. " #" .. bookinfo.series_index
                        end
                        if bookinfo.authors then
                            meta_line = meta_line .. "\n" .. bookinfo.authors
                        end
                    elseif bookinfo.authors then
                        meta_line = bookinfo.authors
                    end
                end

                local strip_content_h = title_strip_h - Screen:scaleBySize(title_cfg.padding)
                local title_max_h = meta_line and title_line_h or strip_content_h
                local meta_max_h = meta_line and (strip_content_h - title_max_h) or 0

                if self._title_widget then
                    self._title_widget:free(true)
                end
                self._title_widget = TextBoxWidget:new{
                    text = BD.auto(title_text),
                    face = Font:getFace("cfont", title_cfg.font_size),
                    width = self.width - Screen:scaleBySize(8),
                    alignment = "center",
                    fgcolor = title_cfg.text_color,
                    height = title_max_h,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                }

                if self._meta_widget then
                    self._meta_widget:free(true)
                    self._meta_widget = nil
                end
                if meta_line and meta_max_h > 0 then
                    self._meta_widget = TextBoxWidget:new{
                        text = BD.auto(meta_line),
                        face = Font:getFace("cfont", title_cfg.meta_font_size),
                        width = self.width - Screen:scaleBySize(8),
                        alignment = "center",
                        fgcolor = title_cfg.meta_color,
                        height = meta_max_h,
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    }
                end
            end
        end

        -- [covers] folder cover logic
        if feat("folder_covers") and not self._foldercover_processed and not self.menu.no_refresh_covers and self.do_cover_image then
            if not (self.entry.is_file or self.entry.file) and self.mandatory then
                local dir_path = self.entry and self.entry.path
                if dir_path then
                    self._foldercover_processed = true

                    local cover_file = findCover(dir_path)
                    if cover_file then
                        local success, w, h = pcall(function()
                            local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                            tmp_img:_render()
                            local orig_w = tmp_img:getOriginalWidth()
                            local orig_h = tmp_img:getOriginalHeight()
                            tmp_img:free()
                            return orig_w, orig_h
                        end)
                        if success then
                            self:_setFolderCover { file = cover_file, w = w, h = h }
                            return
                        end
                    end

                    self.menu._dummy = true
                    local entries = self.menu:genItemTableFromPath(dir_path)
                    self.menu._dummy = false
                    if entries then
                        for _, entry in ipairs(entries) do
                            if entry.is_file or entry.file then
                                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover and bookinfo.cover_fetched
                                   and not bookinfo.ignore_cover and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                                    self:_setFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        -- [series] series group cover logic
        if self.entry and self.entry.is_series_group and not self._seriescover_processed and self.do_cover_image then
            self._seriescover_processed = true

            local series_items = self.entry.series_items
            if series_items and #series_items > 0 then
                if not self.mandatory then
                    self.mandatory = tostring(#series_items) .. " \u{F016}"
                end

                for _, book_entry in ipairs(series_items) do
                    if book_entry.path then
                        local bookinfo = BookInfoManager:getBookInfo(book_entry.path, true)
                        if bookinfo
                            and bookinfo.cover_bb
                            and bookinfo.has_cover
                            and bookinfo.cover_fetched
                            and not bookinfo.ignore_cover
                            and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs) then
                            if self._setFolderCover then
                                self:_setFolderCover({
                                    data = bookinfo.cover_bb,
                                    w = bookinfo.cover_w,
                                    h = bookinfo.cover_h
                                })
                            end
                            break
                        end
                    end
                end
            end
        end

        -- Shrink directory widget for items without folder covers (go-up item, uncovered folders)
        -- so they vertically align with folder cards that use cover_h.
        -- Widget tree: FrameContainer{ OverlapGroup{ CenterContainer, BottomContainer } }
        if self.is_directory and not self._folder_frame_dimen then
            local existing = self._underline_container and self._underline_container[1]
            if existing then
                local cover_h = self.height - title_strip_h - card_gap_px
                local margin = existing.margin or 0
                local padding = existing.padding or 0
                local bs = existing.bordersize or 0
                local inner_h = cover_h - (margin + padding + bs) * 2

                existing.height = cover_h
                if existing.dimen then existing.dimen.h = cover_h end

                local overlap = existing[1]  -- OverlapGroup
                if overlap and overlap.dimen then
                    overlap.dimen.h = inner_h
                    for _, child in ipairs(overlap) do
                        if child.dimen then child.dimen.h = inner_h end
                    end
                end
            end
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        local border_size = 0
        local cover_h = self.height - title_strip_h - card_gap_px
        local frame_dimen = getAspectRatioAdjustedDimensions(self.width, cover_h, border_size)
        local image_width = frame_dimen.w - 2 * border_size
        local image_height = frame_dimen.h - 2 * border_size

        local image = img.file and
            ImageWidget:new { file = img.file, width = image_width, height = image_height, stretch_limit_percentage = stretch_limit } or
            ImageWidget:new { image = img.data, width = image_width, height = image_height, stretch_limit_percentage = stretch_limit }

        local image_widget = FrameContainer:new {
            padding = 0, bordersize = border_size, image, overlap_align = "center",
        }

        local image_size = image:getSize()

        -- Compute item count for nbitems badge and meta line
        local item_count = 0
        if self.mandatory then
            local count_str = self.mandatory:match("(%d+)")
            if count_str then item_count = tonumber(count_str) end
        end

        -- Build folder title/meta widgets for card layout (painted in paintTo)
        if self._folder_title_widget then
            self._folder_title_widget:free(true)
            self._folder_title_widget = nil
        end
        if self._folder_meta_widget then
            self._folder_meta_widget:free(true)
            self._folder_meta_widget = nil
        end

        if settings.show_folder_name.get() then
            local text = self.text
            if text:match("/$") then text = text:sub(1, -2) end
            text = BD.directory(capitalize(text))

            local has_folder_meta = item_count > 0
                or (self.entry and self.entry.is_series_group and self.entry._series_author)
            local strip_content_h = title_strip_h - Screen:scaleBySize(title_cfg.padding)
            local title_max_h = has_folder_meta and (title_line_h * 2) or strip_content_h
            local meta_max_h = has_folder_meta and (strip_content_h - title_max_h) or 0

            self._folder_title_widget = TextBoxWidget:new{
                text = text,
                face = Font:getFace("cfont", title_cfg.font_size),
                width = self.width - Screen:scaleBySize(8),
                alignment = "center",
                bold = true,
                fgcolor = title_cfg.text_color,
                height = title_max_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            }

            if has_folder_meta and meta_max_h > 0 then
                local meta_text
                if self.entry and self.entry.is_series_group and self.entry._series_author then
                    meta_text = self.entry._series_author
                else
                    meta_text = tostring(item_count) .. " " .. (item_count == 1 and _("book") or _("books"))
                end
                self._folder_meta_widget = TextBoxWidget:new{
                    text = meta_text,
                    face = Font:getFace("cfont", title_cfg.meta_font_size),
                    width = self.width - Screen:scaleBySize(8),
                    alignment = "center",
                    fgcolor = title_cfg.meta_color,
                    height = meta_max_h,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                }
            end
        end

        local nbitems_widget

        if item_count > 0 then
            local nbitems = TextWidget:new {
                text = tostring(item_count),
                face = Font:getFace("cfont", Folder.face.nb_items_font_size),
                bold = true, padding = 0
            }

            local nb_size = math.max(nbitems:getSize().w, nbitems:getSize().h)
            nbitems_widget = BottomContainer:new {
                dimen = frame_dimen,
                RightContainer:new {
                    dimen = {
                        w = frame_dimen.w - Folder.face.nb_items_margin,
                        h = nb_size + Folder.face.nb_items_margin * 2,
                    },
                    FrameContainer:new {
                        padding = 2, bordersize = Folder.face.border_size,
                        radius = math.ceil(nb_size), background = Blitbuffer.COLOR_GRAY_E,
                        CenterContainer:new { dimen = { w = nb_size, h = nb_size }, nbitems },
                    },
                },
                overlap_align = "center",
            }
        else
            nbitems_widget = VerticalSpan:new { width = 0 }
        end

        self._folder_frame_dimen = frame_dimen
        self._folder_image_size = image_size

        local widget = CenterContainer:new {
            dimen = { w = self.width, h = cover_h },
            CenterContainer:new {
                dimen = { w = self.width, h = cover_h },
                OverlapGroup:new {
                    dimen = frame_dimen,
                    image_widget,
                    nbitems_widget,
                },
            },
        }

        if self._underline_container[1] then
            self._underline_container[1]:free()
        end
        self._underline_container[1] = widget
    end

    function MosaicMenuItem:_getTextBox(dimen)
        local text = self.text
        if text:match("/$") then text = text:sub(1, -2) end
        text = BD.directory(capitalize(text))

        local available_height = dimen.h
        local dir_font_size = Folder.face.dir_max_font_size
        local directory

        while true do
            if directory then directory:free(true) end
            directory = TextBoxWidget:new {
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then break end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end
        return directory
    end

    -- Capture modules needed for overlay suppression during orig_paintTo
    local ProgressWidget = require("ui/widget/progresswidget")
    local ReadCollection = require("readcollection")
    local orig_ProgressWidget_paintTo = ProgressWidget.paintTo
    local orig_isFileInCollections = ReadCollection.isFileInCollections
    local orig_BookInfoManager_getSetting = BookInfoManager.getSetting

    -- MosaicMenuItem.paintTo -- ONE override
    local _dbg_paint_seen = {}
    function MosaicMenuItem:paintTo(bb, x, y)
        -- Temporarily suppress original CoverBrowser overlays so they don't
        -- double-render with our custom ones:
        -- 1. Zero out corner_mark_size (suppresses original triangular corner marks)
        local saved_corner_mark_size
        if corner_mark_size_idx then
            _, saved_corner_mark_size = debug.getupvalue(orig_paintTo, corner_mark_size_idx)
            debug.setupvalue(orig_paintTo, corner_mark_size_idx, 0)
        end
        -- 2. Replace ProgressWidget.paintTo with noop (suppresses original progress bar)
        ProgressWidget.paintTo = function() end
        -- 3. Make ReadCollection.isFileInCollections return false (suppresses collection star)
        ReadCollection.isFileInCollections = function() return false end
        -- 4. Override BookInfoManager:getSetting("no_hint_description") to return true (suppresses hint)
        BookInfoManager.getSetting = function(self_bim, key, ...)
            if key == "no_hint_description" then return true end
            return orig_BookInfoManager_getSetting(self_bim, key, ...)
        end

        local wp_bg
        if feat("wallpaper_mode") and feat("rounded_corners") and CORNER_R > 0 then
            local r = CORNER_R
            wp_bg = {}
            wp_bg.top = Blitbuffer.new(self.width, r, bb:getType())
            wp_bg.top:blitFrom(bb, 0, 0, x, y, self.width, r)
            wp_bg.bot = Blitbuffer.new(self.width, r, bb:getType())
            wp_bg.bot:blitFrom(bb, 0, 0, x, y + self.height - r, self.width, r)
        end

        orig_paintTo(self, bb, x, y)

        -- Restore all originals
        if corner_mark_size_idx then
            debug.setupvalue(orig_paintTo, corner_mark_size_idx, saved_corner_mark_size)
        end
        ProgressWidget.paintTo = orig_ProgressWidget_paintTo
        ReadCollection.isFileInCollections = orig_isFileInCollections
        BookInfoManager.getSetting = orig_BookInfoManager_getSetting

        -- One-shot per-file debug dump (only first paintTo per filepath)
        if DEBUG_ICONS and self.filepath and not _dbg_paint_seen[self.filepath] then
            _dbg_paint_seen[self.filepath] = true
            local fname = self.filepath:match("[^/]+$") or self.filepath
            logger.info("[custom-icons] paintTo:", fname,
                "| is_dir:", tostring(self.is_directory),
                "| deleted:", tostring(self.file_deleted),
                "| status:", tostring(self.status),
                "| pct:", tostring(self.percent_finished),
                "| opened:", tostring(self.been_opened),
                "| hint:", tostring(self.do_hint_opened),
                "| bookinfo_found:", tostring(self.bookinfo_found),
                "| menu:", tostring(self.menu and self.menu.name))
            local t = self[1] and self[1][1] and self[1][1][1]
            logger.info("[custom-icons]   target:", tostring(t),
                "| target.dimen:", tostring(t and t.dimen))
        end

        -- [covers] Folder path
        if self._folder_frame_dimen and self._folder_image_size then
            if not (self.entry.is_file or self.entry.file) then
                local frame_dimen = self._folder_frame_dimen
                local image_size = self._folder_image_size
                local cover_h = self.height - title_strip_h - card_gap_px
                local fx = x + math.floor((self.width - frame_dimen.w) / 2)
                local fy = y + math.floor((cover_h - frame_dimen.h) / 2)
                local image_x = fx + math.floor((frame_dimen.w - image_size.w) / 2)
                local image_y = fy + math.floor((frame_dimen.h - image_size.h) / 2)

                -- Draw stacked bars above folder cover
                if feat("stacked_bars") then
                local BAR_FILLS     = { Blitbuffer.COLOR_GRAY_5, Blitbuffer.COLOR_GRAY_9, Blitbuffer.COLOR_GRAY_D }
                local BAR_BORDERS   = { Blitbuffer.COLOR_GRAY_1, Blitbuffer.COLOR_GRAY_5, Blitbuffer.COLOR_GRAY_9 }
                local BAR_BORDER_W  = 1
                local BAR_HEIGHT    = Screen:scaleBySize(2)
                local BAR_SPACING   = Screen:scaleBySize(2)
                local COVER_GAP     = Screen:scaleBySize(3)
                local BAR_RATIOS    = { 0.84, 0.74, 0.64 }

                local center_x = image_x + math.floor(image_size.w / 2)
                local current_y = image_y - COVER_GAP - BAR_HEIGHT

                for i = 1, #BAR_RATIOS do
                    local bar_w = math.floor(image_size.w * BAR_RATIOS[i])
                    local bar_x = center_x - math.floor(bar_w / 2)
                    local bar_y = current_y
                    bb:paintRect(bar_x, bar_y, bar_w, BAR_HEIGHT, BAR_FILLS[i])
                    bb:paintBorder(bar_x, bar_y, bar_w, BAR_HEIGHT, BAR_BORDER_W, BAR_BORDERS[i])
                    current_y = bar_y - BAR_HEIGHT - BAR_SPACING
                end
                end -- feat("stacked_bars")

                -- Fill from below cover to cell bottom
                local fill_top = fy + frame_dimen.h
                local fill_h = self.height - (fill_top - y)
                if fill_h > 0 then
                    if feat("wallpaper_mode") then
                        bb:lightenRect(image_x, fill_top, image_size.w, fill_h, 0.75)
                    else
                        bb:paintRect(image_x, fill_top, image_size.w, fill_h, Blitbuffer.COLOR_WHITE)
                    end
                end

                -- Dark grey border around cover
                local cover_border_w = Screen:scaleBySize(folder_border)
                bb:paintBorder(image_x, image_y, image_size.w - 1, image_size.h, cover_border_w, Blitbuffer.COLOR_DARK_GRAY, 0, false)

                if feat("rounded_corners") then
                    if feat("wallpaper_mode") and wp_bg then
                        roundCornersFromBg(bb, wp_bg, x, y, self.height, image_x, image_y, image_size.w, image_size.h, CORNER_R)
                        wp_bg = nil
                    else
                        paintCorners(bb, image_x, image_y, image_size.w, image_size.h)
                    end
                end

                -- Folder title below cover
                if self._folder_title_widget then
                    local strip_top = y + self.height - title_strip_h
                    local tw = self._folder_title_widget:getSize().w
                    local title_x = x + math.floor((self.width - tw) / 2)
                    self._folder_title_widget:paintTo(bb, title_x, strip_top)

                    if self._folder_meta_widget then
                        local mw = self._folder_meta_widget:getSize().w
                        local meta_x = x + math.floor((self.width - mw) / 2)
                        local meta_y = strip_top + self._folder_title_widget:getSize().h
                        self._folder_meta_widget:paintTo(bb, meta_x, meta_y)
                    end
                end
                if self._focused then
                    local bw = Screen:scaleBySize(focus_cfg.border_width)
                    bb:paintRect(x, y + self.height - bw, self.width, bw, focus_cfg.color)
                end
                if wp_bg then wp_bg.top:free(); wp_bg.bot:free(); wp_bg = nil end
                return
            end
        end

        -- [covers] Book path
        local function freeWpBg()
            if wp_bg then
                wp_bg.top:free(); wp_bg.bot:free()
                wp_bg = nil
            end
        end
        if self.is_directory or self.file_deleted then freeWpBg(); return end
        local target = self._cover_frame or (self[1] and self[1][1] and self[1][1][1])
        if not target or not target.dimen then freeWpBg(); return end

        local cover_area_h = self._title_widget and (self.height - title_strip_h - card_gap_px) or self.height
        local fx = x + math.floor((self.width - target.dimen.w) / 2)
        local fy = y + math.floor((cover_area_h - target.dimen.h) / 2)
        local fw, fh = target.dimen.w, target.dimen.h

        -- [covers] Border around cover (inset 1px so corner masks fully cover it)
        local cover_border = Screen:scaleBySize(0.5)
        bb:paintBorder(fx, fy, fw - 1, fh, cover_border, Blitbuffer.COLOR_DARK_GRAY, 0, false)

        -- [card] Fill from below cover to cell bottom (gap + text area)
        if self._title_widget then
            local fill_top = y + cover_area_h
            local fill_h = self.height - cover_area_h
            if feat("wallpaper_mode") then
                bb:lightenRect(fx, fill_top, fw, fill_h, 0.75)
            else
                bb:paintRect(fx, fill_top, fw, fill_h, Blitbuffer.COLOR_WHITE)
            end
        end

        if feat("rounded_corners") then
            if feat("wallpaper_mode") and wp_bg then
                roundCornersFromBg(bb, wp_bg, x, y, self.height, fx, fy, fw, fh, CORNER_R)
                wp_bg = nil
            else
                paintCorners(bb, fx, fy, fw, fh)
            end
        end

        -- [overlays] Progress bar (hidden below MIN_PERCENT and at/above NEAR_COMPLETE_PERCENT)
        local pf = self.percent_finished
        local _has_bar = feat("progress_bar") and pf and self.status ~= "complete"
            and pf >= bar_cfg.MIN_PERCENT and pf < bar_cfg.NEAR_COMPLETE_PERCENT
        local bar_bottom_y  -- y coordinate of bottom edge of bar (used by pages badge)
        if _has_bar then
            local bar_w = math.max(1, math.floor(fw * 0.92))
            local bar_h = bar_cfg.H
            local bar_x = I(fx + math.floor((fw - bar_w) / 2))
            local bar_y = I(fy + math.floor(fh * bar_cfg.PERCENT_POS))

            bb:paintRoundedRect(
                bar_x - bar_cfg.BORDER_W, bar_y - bar_cfg.BORDER_W,
                bar_w + 2 * bar_cfg.BORDER_W, bar_h + 2 * bar_cfg.BORDER_W,
                bar_cfg.BORDER_COLOR, bar_cfg.RADIUS + bar_cfg.BORDER_W
            )
            bb:paintRoundedRect(bar_x, bar_y, bar_w, bar_h, bar_cfg.TRACK_COLOR, bar_cfg.RADIUS)

            local p = math.max(0, math.min(1, pf))
            local fw_w = math.max(1, math.floor(bar_w * p + 0.5))
            local fill_color = (self.status == "abandoned") and bar_cfg.ABANDONED_COLOR or bar_cfg.FILL_COLOR
            bb:paintRoundedRect(bar_x, bar_y, fw_w, bar_h, fill_color, bar_cfg.RADIUS)

            bar_bottom_y = bar_y + bar_h
        end

        -- [overlays] Status icons (dogear at bottom-right)
        -- Treat books at/above NEAR_COMPLETE_PERCENT as visually complete
        local effective_status = self.status
        if pf and pf >= bar_cfg.NEAR_COMPLETE_PERCENT and effective_status ~= "complete" and effective_status ~= "abandoned" then
            effective_status = "complete"
        end

        local _show_dogear = feat("dogear") and (effective_status == "complete"
            or effective_status == "abandoned"
            or (
                self.percent_finished
                and self.percent_finished >= bar_cfg.MIN_PERCENT
                and (
                    (self.do_hint_opened and self.been_opened)
                    or self.menu.name == "history"
                    or self.menu.name == "collections"
                )
            ))
        if DEBUG_ICONS and self.filepath and _dbg_paint_seen[self.filepath] == true then
            _dbg_paint_seen[self.filepath] = "logged"
            local fname = self.filepath:match("[^/]+$") or self.filepath
            logger.info("[custom-icons] dogear?", tostring(_show_dogear), "for", fname)
        end
        if _show_dogear then
            local icon_corner_mark_size = math.floor(math.min(self.width, self.height) / 8)

            local icon_ix, icon_iy

            local icon_inset_x = Screen:scaleBySize(4)
            if BD.mirroredUILayout() then
                icon_ix = math.floor((self.width - fw) / 2) + icon_inset_x
            else
                icon_ix = self.width - math.ceil((self.width - fw) / 2) - icon_corner_mark_size - icon_inset_x
            end
            local corner_inset = Screen:scaleBySize(8)
            icon_iy = cover_area_h - math.ceil((cover_area_h - fh) / 2) - icon_corner_mark_size - corner_inset

            local mark

            if effective_status == "abandoned" then
                mark = IconWidget:new({
                    icon = BD.mirroredUILayout() and "dogear.abandoned.rtl" or "dogear.abandoned",
                    width = icon_corner_mark_size,
                    height = icon_corner_mark_size,
                    alpha = true,
                })
            elseif effective_status == "complete" then
                mark = IconWidget:new({
                    icon = BD.mirroredUILayout() and "dogear.complete.rtl" or "dogear.complete",
                    width = icon_corner_mark_size,
                    height = icon_corner_mark_size,
                    alpha = true,
                })
            else
                mark = IconWidget:new({
                    icon = "dogear.reading",
                    rotation_angle = BD.mirroredUILayout() and 270 or 0,
                    width = icon_corner_mark_size,
                    height = icon_corner_mark_size,
                    alpha = true,
                })
            end

            if mark then
                mark:paintTo(bb, x + icon_ix, y + icon_iy)
            end
        end

        -- [overlays] Pages badge (bottom-left, non-complete books)
        local _show_pages = feat("pages_badge") and not self.is_directory and not self.file_deleted
            and self.status ~= "complete"
        if DEBUG_ICONS and self.filepath and _dbg_paint_seen[self.filepath] == "logged" then
            _dbg_paint_seen[self.filepath] = "done"
            local fname = self.filepath:match("[^/]+$") or self.filepath
            logger.info("[custom-icons] pages_gate?", tostring(_show_pages), "for", fname,
                "| is_dir:", tostring(self.is_directory),
                "| deleted:", tostring(self.file_deleted),
                "| status:", tostring(self.status),
                "| opened:", tostring(self.been_opened),
                "| self.pages:", tostring(self.pages))
        end
        if _show_pages then
            -- Source 1: sidecar pages (accurate for all opened books; set in update)
            local page_count = self.pages
            -- Source 2: BookInfoManager DB (works for unread PDF/DjVu, nil for EPUBs)
            if not page_count and self.filepath then
                local bookinfo = BookInfoManager:getBookInfo(self.filepath, false)
                if bookinfo and bookinfo.pages then
                    page_count = bookinfo.pages
                end
            end

            if page_count then
                local page_text = page_count .. " p."
                local pfont_size = pages_cfg.font_size

                local pages_text = TextWidget:new({
                    text = page_text,
                    face = Font:getFace("cfont", pfont_size),
                    alignment = "left",
                    fgcolor = pages_cfg.text_color,
                    bold = true,
                    padding = 2,
                })

                local pages_badge = FrameContainer:new({
                    linesize = Screen:scaleBySize(2),
                    radius = Screen:scaleBySize(pages_cfg.border_corner_radius),
                    color = pages_cfg.border_color,
                    bordersize = pages_cfg.border_thickness,
                    background = pages_cfg.background_color,
                    padding = Screen:scaleBySize(2),
                    margin = 0,
                    pages_text,
                })

                local cover_left = x + math.floor((self.width - fw) / 2)
                local cover_bottom = y + cover_area_h - math.floor((cover_area_h - fh) / 2)
                local badge_w, badge_h = pages_badge:getSize().w, pages_badge:getSize().h

                local pos_x_badge = cover_left + pages_cfg.inset_x
                local pos_y_badge = cover_bottom - badge_h - pages_cfg.inset_y

                pages_badge:paintTo(bb, pos_x_badge, pos_y_badge)
            end
        end

        -- [overlays] Percent badge (top-right, in-progress books)
        if feat("percent_badge") and not self.is_directory and self.status ~= "complete" and self.percent_finished then
            if
                (self.do_hint_opened and self.been_opened)
                or self.menu.name == "history"
                or self.menu.name == "collections"
            then
                local percent_text = string.format("%d%%", math.floor(self.percent_finished * 100))
                local pct_font_size = percent_cfg.text_size
                local percent_widget = TextWidget:new({
                    text = percent_text,
                    font_size = pct_font_size,
                    face = Font:getFace("cfont", pct_font_size),
                    alignment = "center",
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    bold = true,
                    max_width = Screen:scaleBySize(20),
                    truncate_with_ellipsis = true,
                })

                local PBADGE_W = Screen:scaleBySize(percent_cfg.badge_w)
                local PBADGE_H = Screen:scaleBySize(percent_cfg.badge_h)
                local PINSET_X = Screen:scaleBySize(percent_cfg.move_on_x)
                local PINSET_Y = Screen:scaleBySize(percent_cfg.move_on_y)
                local TEXT_PAD = Screen:scaleBySize(6)

                local pfx = x + math.floor((self.width - fw) / 2)
                local pfy = y + math.floor((cover_area_h - fh) / 2)
                local pfw = fw

                local percent_badge_icon = IconWidget:new({ icon = "percent.badge", alpha = true })
                percent_badge_icon.width = PBADGE_W
                percent_badge_icon.height = PBADGE_H

                local bx = pfx + pfw - PBADGE_W - PINSET_X
                local by = pfy + PINSET_Y
                bx, by = math.floor(bx), math.floor(by)

                percent_badge_icon:paintTo(bb, bx, by)
                percent_widget.alignment = "center"
                percent_widget.truncate_with_ellipsis = false
                percent_widget.max_width = PBADGE_W - 2 * TEXT_PAD

                local ts = percent_widget:getSize()
                local tx = bx + math.floor((PBADGE_W - ts.w) / 2)
                local ty = by + math.floor((PBADGE_H - ts.h) / 2) - Screen:scaleBySize(percent_cfg.bump_up)
                percent_widget:paintTo(bb, math.floor(tx), math.floor(ty))
            end
        end

        -- [overlays] Series badge (top-center)
        if feat("series_badge") and self.has_series_badge and self.series_badge then
            local series_badge_size = self.series_badge:getSize()
            local sbadge_x = target.dimen.x + math.floor((target.dimen.w - series_badge_size.w) / 2)
            local sbadge_y = target.dimen.y + 5

            self.series_badge:paintTo(bb, sbadge_x, sbadge_y)
        end

        -- [overlays] New badge (top-left, recently added unread books)
        if feat("new_badge") and self._is_new then
            local NBADGE_W = Screen:scaleBySize(new_badge_cfg.badge_w)
            local NBADGE_H = Screen:scaleBySize(new_badge_cfg.badge_h)

            local new_badge_icon = IconWidget:new({ icon = "new", alpha = true })
            new_badge_icon.width = NBADGE_W
            new_badge_icon.height = NBADGE_H

            local cover_left = x + math.floor((self.width - fw) / 2)
            local cover_top = y + math.floor((cover_area_h - fh) / 2)
            local ninset_x = Screen:scaleBySize(new_badge_cfg.inset_x)
            local ninset_y = Screen:scaleBySize(new_badge_cfg.inset_y)

            new_badge_icon:paintTo(bb, cover_left + ninset_x, cover_top + ninset_y)
        end

        -- [title] Paint title and meta text below the cover image
        if self._title_widget and target and target.dimen then
            local strip_top = y + self.height - title_strip_h
            local tw = self._title_widget:getSize().w
            local th = self._title_widget:getSize().h
            local title_x = x + math.floor((self.width - tw) / 2)
            self._title_widget:paintTo(bb, title_x, strip_top)

            if self._meta_widget then
                local mw = self._meta_widget:getSize().w
                local meta_x = x + math.floor((self.width - mw) / 2)
                local meta_y = strip_top + th
                self._meta_widget:paintTo(bb, meta_x, meta_y)
            end
        end

        if self._focused then
            local bw = Screen:scaleBySize(focus_cfg.border_width)
            bb:paintRect(x, y + self.height - bw, self.width, bw, focus_cfg.color)
        end

    end

    function MosaicMenuItem:onFocus()
        self._focused = true
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end

    function MosaicMenuItem:onUnfocus()
        self._focused = false
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end

    -- MosaicMenuItem.free
    if orig_free then
        function MosaicMenuItem:free()
            if self._series_text then
                self._series_text:free(true)
                self._series_text = nil
            end

            if self.series_badge then
                self.series_badge:free(true)
                self.series_badge = nil
            end

            self.series_index = nil
            self.has_series_badge = nil
            self._cover_frame = nil

            if self._title_widget then
                self._title_widget:free(true)
                self._title_widget = nil
            end

            if self._meta_widget then
                self._meta_widget:free(true)
                self._meta_widget = nil
            end

            if self._folder_title_widget then
                self._folder_title_widget:free(true)
                self._folder_title_widget = nil
            end
            if self._folder_meta_widget then
                self._folder_meta_widget:free(true)
                self._folder_meta_widget = nil
            end

            orig_free(self)
        end
    end

    -- AutomaticSeries methods
    local function isDirectory(item)
        return item.is_directory or (item.attr and item.attr.mode == "directory") or item.mode == "directory"
    end

    local AutomaticSeries = {}

    function AutomaticSeries:processItemTable(item_table, file_chooser)
        if not file_chooser or not item_table then return end

        if file_chooser.show_current_dir_for_hold then return end

        logger.dbg("AutomaticSeries: Processing Items")

        local collate, collate_id = file_chooser:getCollate()
        local reverse = G_reader_settings:isTrue("reverse_collate")
        local sort_func = file_chooser:getSortingFunction(collate, reverse)
        local mixed = G_reader_settings:isTrue("collate_mixed") and collate.can_collate_mixed

        local is_name_sort = (collate_id == "strcoll" or collate_id == "natural" or collate_id == "title")

        -- Pass 1: Pre-scan to count books per series
        local series_book_count = {}
        for _, item in ipairs(item_table) do
            if item.is_file and item.path then
                local doc_props = item.doc_props or BookInfoManager:getDocProps(item.path)
                if doc_props and doc_props.series and doc_props.series ~= "\u{FFFF}" then
                    series_book_count[doc_props.series] = (series_book_count[doc_props.series] or 0) + 1
                end
            end
        end

        local series_map = {}
        local processed_list = {}

        local book_count = 0
        local non_series_book_count = 0

        -- Pass 2: Build groups only for multi-book series
        for _, item in ipairs(item_table) do
            if item.is_go_up then
                table.insert(processed_list, item)
            else
                if not item.sort_percent then item.sort_percent = 0 end
                if not item.percent_finished then item.percent_finished = 0 end
                if not item.opened then item.opened = false end

                local is_file = item.is_file
                local series_handled = false

                if is_file and item.path then
                    book_count = book_count + 1

                    local doc_props = item.doc_props or BookInfoManager:getDocProps(item.path)
                    if doc_props and doc_props.series and doc_props.series ~= "\u{FFFF}"
                       and series_book_count[doc_props.series] >= 2 then
                        local series_name = doc_props.series

                        item._series_index = doc_props.series_index or 0

                        if not series_map[series_name] then
                            logger.dbg("AutomaticSeries: Found series", series_name)

                            local group_attr = {}
                            if item.attr then
                                for k, v in pairs(item.attr) do group_attr[k] = v end
                            end
                            group_attr.mode = "directory"

                            local group_item = {
                                text = series_name,
                                is_file = false,
                                is_directory = true,
                                path = (item.path:match("(.*/)") or item.path) .. series_name,
                                is_series_group = true,
                                _series_author = doc_props.authors,
                                series_items = { item },
                                attr = group_attr,
                                mode = "directory",
                                sort_percent = item.sort_percent,
                                percent_finished = item.percent_finished,
                                opened = item.opened,
                                doc_props = item.doc_props or {
                                    series = series_name,
                                    series_index = 0,
                                    display_title = series_name,
                                },
                                suffix = item.suffix,
                            }
                            series_map[series_name] = group_item
                            table.insert(processed_list, group_item)
                        else
                            table.insert(series_map[series_name].series_items, item)
                        end
                        series_handled = true
                    else
                        non_series_book_count = non_series_book_count + 1
                    end
                end

                if not series_handled then
                    table.insert(processed_list, item)
                end
            end
        end

        logger.dbg("AutomaticSeries: Done grouping.")

        local series_count = 0
        for _ in pairs(series_map) do
            series_count = series_count + 1
            if series_count > 1 then break end
        end

        if series_count == 1 and non_series_book_count == 0 and book_count > 0 then
            logger.dbg("AutomaticSeries: Skipping - all books from same series")
            return
        end

        for _, group in pairs(series_map) do
            group.mandatory = tostring(#group.series_items) .. " \u{F016}"
            table.sort(group.series_items, function(a, b)
                return (a._series_index or 0) < (b._series_index or 0)
            end)
        end

        local final_table = {}

        if mixed then
            if is_name_sort then
                local up_item
                local to_sort = {}
                for _, item in ipairs(processed_list) do
                    if item.is_go_up then up_item = item else table.insert(to_sort, item) end
                end
                local ok, err = pcall(table.sort, to_sort, sort_func)
                if not ok then
                    logger.warn("AutomaticSeries: Sort failed, using unsorted list:", err)
                end

                if up_item then table.insert(final_table, up_item) end
                for _, item in ipairs(to_sort) do table.insert(final_table, item) end
            else
                final_table = processed_list
            end
        else
            local dirs = {}
            local files = {}
            local up_item

            for _, item in ipairs(processed_list) do
                if item.is_go_up then
                    up_item = item
                elseif isDirectory(item) then
                    table.insert(dirs, item)
                else
                    table.insert(files, item)
                end
            end

            local ok, err = pcall(table.sort, dirs, sort_func)
            if not ok then
                logger.warn("AutomaticSeries: Sort failed, using unsorted list:", err)
            end

            if up_item then table.insert(final_table, up_item) end
            for _, d in ipairs(dirs) do table.insert(final_table, d) end
            for _, f in ipairs(files) do table.insert(final_table, f) end
        end

        logger.dbg("AutomaticSeries: Done sorting.")

        for k in pairs(item_table) do item_table[k] = nil end
        for i, v in ipairs(final_table) do item_table[i] = v end
    end

    function AutomaticSeries:openSeriesGroup(file_chooser, group_item)
        if not file_chooser then
            return
        end

        local items = group_item.series_items

        local parent_path = file_chooser.path

        current_series_group = {
            series_name = group_item.text,
            parent_path = parent_path,
        }

        logger.dbg("AutomaticSeries: Opening series:", group_item.text)

        local up_item_already_present = items[1] and items[1].is_go_up

        local is_browser_up_folder_enabled = file_chooser._changeLeftIcon ~= nil
            and G_reader_settings:readSetting("filemanager_hide_up_folder", false)

        if not up_item_already_present and not is_browser_up_folder_enabled then
            local up_item = {
                text = BD.mirroredUILayout() and BD.ltr("../ \u{2B06}") or "\u{2B06} ../",
                is_directory = true,
                path = parent_path,
                is_go_up = true,
            }
            table.insert(items, 1, up_item)
        end

        items.is_in_series_view = true
        items.parent_path = parent_path

        file_chooser:switchItemTable(nil, items, nil, nil, group_item.text)

        if is_browser_up_folder_enabled then
            file_chooser:_changeLeftIcon(Icon.up, function() file_chooser:onFolderUp() end)
        end
    end

    local function exitVirtualFolderIfNeeded(file_chooser)
        if file_chooser and file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            local parent_path = file_chooser.item_table.parent_path
            if parent_path then
                logger.dbg("AutomaticSeries: Exiting virtual folder, returning to parent path:", parent_path)
                if current_series_group then
                    current_series_group.should_restore_focus = true
                end
                file_chooser:changeToPath(parent_path)
                return true
            end
        end
        return false
    end

    -- FileChooser hooks
    local old_setSubTitle = TitleBar.setSubTitle
    TitleBar.setSubTitle = function(self, subtitle, no_refresh)
        if current_series_group then
            return old_setSubTitle(self, current_series_group.series_name, no_refresh)
        end
        return old_setSubTitle(self, subtitle, no_refresh)
    end

    local old_updateItems = FileChooser.updateItems
    local old_onMenuSelect = FileChooser.onMenuSelect
    local old_onFolderUp = FileChooser.onFolderUp
    local old_changeToPath = FileChooser.changeToPath
    local old_refreshPath = FileChooser.refreshPath
    local old_goHome = FileChooser.goHome
    local old_switchItemTable = FileChooser.switchItemTable

    FileChooser.switchItemTable = function(file_chooser, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
        if feat("image_as_cover") then
            filterMatchingImages(new_item_table)
        end

        if feat("virtual_series") and new_item_table and not new_item_table.is_in_series_view then
            AutomaticSeries:processItemTable(new_item_table, file_chooser)
        end

        return old_switchItemTable(file_chooser, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
    end

    FileChooser.goHome = function(file_chooser)
        if file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            if current_series_group then
                current_series_group.should_restore_focus = true
            end

            local parent_path = file_chooser.item_table.parent_path
            local home_dir = G_reader_settings:readSetting("home_dir") or require("device").home_dir

            if parent_path and home_dir and parent_path == home_dir then
                file_chooser:changeToPath(parent_path)
                return true
            end
        end
        return old_goHome(file_chooser)
    end

    FileChooser.refreshPath = function(file_chooser)
        old_refreshPath(file_chooser)
        if feat("virtual_series") and current_series_group then
            local series_name = current_series_group.series_name
            for _, item in ipairs(file_chooser.item_table) do
                if item.is_series_group and item.text == series_name then
                    AutomaticSeries:openSeriesGroup(file_chooser, item)
                    break
                end
            end
        end
    end

    FileChooser.onFolderUp = function(file_chooser)
        if exitVirtualFolderIfNeeded(file_chooser) then
            return true
        end
        return old_onFolderUp(file_chooser)
    end

    FileChooser.onMenuSelect = function(file_chooser, item)
        if feat("virtual_series") and item.is_series_group then
            AutomaticSeries:openSeriesGroup(file_chooser, item)
            return true
        end

        return old_onMenuSelect(file_chooser, item)
    end

    FileChooser.changeToPath = function(file_chooser, path, ...)
        if file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            local parent_path = file_chooser.item_table.parent_path
            if parent_path and path and (path:match("/%.%.") or path:match("^%.%.")) then
                path = parent_path
            end
            if current_series_group then
                current_series_group.should_restore_focus = true
            end
        else
            current_series_group = nil
        end

        return old_changeToPath(file_chooser, path, ...)
    end

    FileChooser.updateItems = function(file_chooser, ...)
        if not feat("virtual_series") then
            current_series_group = nil
            return old_updateItems(file_chooser, ...)
        end

        if not file_chooser.item_table or #file_chooser.item_table == 0 then
            return old_updateItems(file_chooser, ...)
        end

        if file_chooser.item_table.is_in_series_view then
            return old_updateItems(file_chooser, ...)
        end

        if current_series_group and current_series_group.should_restore_focus
           and file_chooser.item_table and #file_chooser.item_table > 0 then
            logger.dbg("AutomaticSeries: Looking for series to restore focus:", current_series_group.series_name)
            for index, item in ipairs(file_chooser.item_table) do
                if item.is_series_group and item.text == current_series_group.series_name then
                    logger.dbg("AutomaticSeries: Found series group at index:", index)
                    local page = math.ceil(index / file_chooser.perpage)
                    local select_number = ((index - 1) % file_chooser.perpage) + 1
                    file_chooser.page = page
                    file_chooser.path_items[file_chooser.path] = index
                    current_series_group = nil
                    return old_updateItems(file_chooser, select_number)
                end
            end
            current_series_group = nil
        end

        return old_updateItems(file_chooser, ...)
    end

    -- plugin.addToMainMenu -- ONE override
    local orig_addToMainMenu = plugin.addToMainMenu
    function plugin:addToMainMenu(menu_items)
        orig_addToMainMenu(self, menu_items)

        -- [covers] inject folder-name settings into Mosaic submenu
        if menu_items.filebrowser_settings then
            local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
            if item then
                item.sub_item_table[#item.sub_item_table].separator = true
                for i, setting in pairs(settings) do
                    if not getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"), setting.text) then
                        table.insert(item.sub_item_table, {
                            text = setting.text,
                            checked_func = function() return setting.get() end,
                            callback = function()
                                setting.toggle()
                                self.ui.file_chooser:updateItems()
                            end,
                        })
                    end
                end
            end

            -- [features] inject feature toggle submenu
            local feature_items = {
                { key = "cover_aspect_ratio", text = _("Stretched covers (aspect ratio)"), full_refresh = true },
                { key = "rounded_corners",    text = _("Rounded corner overlays") },
                { key = "folder_covers",      text = _("Folder cover images"), full_refresh = true },
                { key = "stacked_bars",       text = _("Stacked bars above folders") },
                { key = "title_strip",        text = _("Title strip below covers"), full_refresh = true },
                { key = "progress_bar",       text = _("Reading progress bar") },
                { key = "percent_badge",      text = _("Percent read badge") },
                { key = "pages_badge",        text = _("Page count badge") },
                { key = "series_badge",       text = _("Series index badge"), full_refresh = true },
                { key = "dogear",             text = _("Status dogear icons") },
                { key = "new_badge",          text = _("New book badge") },
                { key = "image_as_cover",     text = _("Image file as book cover"), full_refresh = true },
                { key = "virtual_series",     text = _("Group series into virtual folders"), full_refresh = true },
                { key = "wallpaper_mode",    text = _("Wallpaper-compatible mode"), full_refresh = true },
            }

            local feat_sub_items = {}
            for _, fi in ipairs(feature_items) do
                table.insert(feat_sub_items, {
                    text = fi.text,
                    checked_func = function() return feat(fi.key) end,
                    callback = function()
                        toggleFeat(fi.key)
                        if fi.full_refresh then
                            self.ui.file_chooser:refreshPath()
                        else
                            self.ui.file_chooser:updateItems()
                        end
                    end,
                })
            end

            if item then
                table.insert(item.sub_item_table, {
                    text = _("Visual features"),
                    separator = true,
                    sub_item_table = feat_sub_items,
                })
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchVisualOverhaul)

end)
if not ok then
    local logger = require("logger")
    logger.warn("PATCH FAILED: 2--visual-overhaul:", tostring(err))
end
