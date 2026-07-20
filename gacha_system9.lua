print("(Loaded) Gacha System - Custom")

--[[
    ============================================================
    GACHA SYSTEM - GTPS.Host
    ============================================================
    Commands:
      /gachamenu   -> Menu gacha untuk player
      /panelgacha  -> Panel admin untuk mengatur gacha (Owner only)

    UPDATE TERBARU:
    - Item hadiah sekarang punya tier: legend / rare / basic, dan
      jumlah (amount). Ditampilkan berkelompok di dialog gacha,
      contoh:
          > Legend
          - Blue Gem Lock : 5
          > Rare
          - Diamond Lock : 5
          > Basic
          - World Lock : 5
    - Panel "Edit Gacha" sekarang per-item (bukan CSV), tiap item
      bisa di-Edit (ganti ID) atau Delete, dan bisa nambah item baru
      dengan Id Items + Category (legend/rare/basic).
    - Animasi spin sekarang menampilkan teks "Arrow >> Nama : Jumlah"
      yang berganti-ganti, makin lama makin lambat, lalu berhenti di
      hadiah yang benar-benar didapat.
    - Peluang tier: Basic paling sering, Rare sedang, Legend paling
      jarang (lihat TIER_WEIGHT di bawah, bisa diubah manual).
    - OWNER_ROLE_ID = 51 -> Role ID untuk Owner (BUKAN User ID). Dicek
      lewat player:hasRole(51), bukan getUserID().

    SESUAIKAN DULU:
    - TIER_ITEMS sudah diisi ID asli servermu (wl=242, dl=1796, bgl=7188).
    - Icon ID (WELCOME_ICON, TITLE_ICON, ARROW_ICON) sudah sesuai
      permintaanmu (7188, 1796, 482).
]]

local OWNER_ROLE_ID = 51 -- Role ID untuk Owner (bukan User ID)

local TIER_ITEMS = {
    wl  = 242,   -- World Lock
    dl  = 1796,  -- Diamond Lock
    bgl = 7188,  -- Blue Gem Lock
}

local WELCOME_ICON = 7188
local TITLE_ICON    = 1796
local ARROW_ICON    = 482

-- Warna UI dialog per kategori (berdasarkan urutan kategori: 1=Basic,
-- 2=Normal, 3=Special, 4=Event). Kalau kamu tambah kategori baru lewat
-- panel (ID 5+), warnanya fallback ke CATEGORY_COLOR_DEFAULT.
-- Kode warna Growtopia standar -- kalau warnanya kurang pas di client
-- kamu, tinggal ganti kode `X di bawah ini.
local CATEGORY_COLOR = {
    [1] = "`9", -- Basic Gacha  -> Biru Tua
    [2] = "`5", -- Normal Gacha -> Ungu
    [3] = "`6", -- Special Gacha -> Emas
    [4] = "`4", -- Event Gacha  -> Merah
}
local CATEGORY_COLOR_DEFAULT = "`o"

local function getCategoryColor(catID)
    return CATEGORY_COLOR[catID] or CATEGORY_COLOR_DEFAULT
end

-- Urutan tampil & bobot peluang keluarnya tiap tier reward.
-- Basic = paling gampang/sering, Legend = paling langka.
local TIER_ORDER  = { "legend", "rare", "basic" }
local TIER_LABEL  = { legend = "Legend", rare = "Rare", basic = "Basic" }
local TIER_COLOR  = { legend = "`5", rare = "`9", basic = "`w" }
local TIER_WEIGHT = { legend = 5, rare = 25, basic = 70 }

local DATA_KEY = "gacha_system_data"
local gachaData = nil

-- Register command dengan roleRequired, sama seperti pola /spotify.
-- roleRequired = 0 -> Default Role, semua player boleh pakai /gachamenu.
-- /panelgacha juga didaftarkan roleRequired = 0 (lolos gate bawaan),
-- permission sesungguhnya dicek manual lewat hasRole(OWNER_ROLE_ID)
-- di dalam callback, supaya tidak bentrok dengan sistem role bawaan.
registerLuaCommand({ command = "gachamenu", roleRequired = 0, description = "Open the gacha menu" })
registerLuaCommand({ command = "panelgacha", roleRequired = 0, description = "Manage the gacha system (Owner only)" })

-- ================= DATA HANDLING =================

-- Setiap item sekarang berbentuk: { id = itemID, amount = jumlah, tier = "legend"/"rare"/"basic" }
local function defaultData()
    return {
        order = {1, 2, 3, 4},
        categories = {
            [1] = {name = "Basic Gacha",   price = 1, tier = "bgl", items = {}},
            [2] = {name = "Normal Gacha",  price = 1, tier = "bgl", items = {}},
            [3] = {name = "Special Gacha", price = 1, tier = "bgl", items = {}},
            [4] = {name = "Event Gacha",   price = 1, tier = "bgl", items = {}},
        },
        nextID = 5,
    }
end

local function loadGacha()
    local raw = loadStringFromServer(DATA_KEY)
    if raw and raw ~= "" then
        local decoded = json.decode(raw)
        if decoded then
            gachaData = decoded
            return
        end
    end
    gachaData = defaultData()
end

local function saveGacha()
    saveStringToServer(DATA_KEY, json.encode(gachaData))
end

loadGacha()
math.randomseed(os.time())

-- ================= HELPERS =================

local function currencyTierName(tier)
    if tier == "wl" then return "World Lock" end
    if tier == "dl" then return "Diamond Lock" end
    if tier == "bgl" then return "Blue Gem Lock" end
    return tier
end

local function itemDisplayName(itemID)
    local item = getItem(itemID)
    return item and item:getName() or ("Item #" .. tostring(itemID))
end

-- Owner-only (cek Role ID, bukan User ID)
local function isOwner(player)
    return player:hasRole(OWNER_ROLE_ID)
end

-- Hanya Role ID 0 (Default Role) yang boleh pakai /gachamenu
local GACHA_MENU_ROLE_ID = 0
local function isDefaultRole(player)
    return player:hasRole(GACHA_MENU_ROLE_ID)
end

local editSession = {}

-- ================= REWARD LIST DISPLAY =================

-- Bangun baris dialog berisi daftar hadiah berkelompok per tier,
-- contoh:
--   > Legend
--   - Blue Gem Lock : 5
--   > Rare
--   - Diamond Lock : 5
--   > Basic
--   - World Lock : 5
local function buildRewardListLines(cat)
    local lines = {}

    if #cat.items == 0 then
        table.insert(lines, "add_label|small|`oNo rewards configured yet.|left|\n")
        return lines
    end

    for _, tier in ipairs(TIER_ORDER) do
        local itemsInTier = {}
        for _, it in ipairs(cat.items) do
            if it.tier == tier then table.insert(itemsInTier, it) end
        end

        if #itemsInTier > 0 then
            table.insert(lines, "add_label|small|" .. TIER_COLOR[tier] .. "> " .. TIER_LABEL[tier] .. "|left|\n")
            for _, it in ipairs(itemsInTier) do
                table.insert(lines, "add_label|small|`o- " .. itemDisplayName(it.id) .. " : " .. it.amount .. "|left|\n")
            end
            table.insert(lines, "add_spacer|small|\n")
        end
    end

    return lines
end

-- ================= PLAYER: /gachamenu =================

local function showMainMenu(player, msg)
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label_with_icon|big|`oGacha Menu|left|" .. TITLE_ICON .. "|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_label_with_icon|small|`oHello @" .. player:getRealCleanName() .. " welcome back, want gacha?|left|" .. WELCOME_ICON .. "|\n")
    table.insert(t, "add_spacer|small|\n")
    if msg ~= nil and msg ~= "" then
        table.insert(t, "add_label|small|" .. msg .. "|left|\n")
        table.insert(t, "add_spacer|small|\n")
    end

    for _, id in ipairs(gachaData.order) do
        local cat = gachaData.categories[id]
        if cat then
            table.insert(t, "add_button|gacha_cat_" .. id .. "|[ " .. cat.name .. " ]|noflags|0|0|\n")
        end
    end

    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|close|`4Close|noflags|0|0|\n")
    table.insert(t, "end_dialog|gacha_menu_main|||\n")
    player:onDialogRequest(table.concat(t))
end

local function showCategory(player, catID, msg)
    local cat = gachaData.categories[catID]
    if not cat then return end

    local color = getCategoryColor(catID)

    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label_with_icon|big|`o" .. cat.name .. "|left|" .. TITLE_ICON .. "|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_label_with_icon|small|" .. color .. ">>|left|" .. ARROW_ICON .. "|\n")
    table.insert(t, "add_spacer|small|\n")

    for _, line in ipairs(buildRewardListLines(cat)) do
        table.insert(t, line)
    end

    table.insert(t, "add_textbox|`oTips: `4every time you play it will cost your " .. currencyTierName(cat.tier) .. "|left|\n")
    if msg ~= nil and msg ~= "" then
        table.insert(t, "add_spacer|small|\n")
        table.insert(t, "add_label|small|" .. msg .. "|left|\n")
    end
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|gacha_play_" .. catID .. "_1|" .. color .. "[ Play 1 x ] (" .. cat.price .. " " .. cat.tier .. ")|noflags|0|0|\n")
    table.insert(t, "add_button|gacha_play_" .. catID .. "_5|" .. color .. "[ Play 5 x ] (" .. (cat.price * 5) .. " " .. cat.tier .. ")|noflags|0|0|\n")
    table.insert(t, "add_button|gacha_play_" .. catID .. "_10|" .. color .. "[ Play 10 x ] (" .. (cat.price * 10) .. " " .. cat.tier .. ")|noflags|0|0|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|gacha_menu_back|`wBack|noflags|0|0|\n")
    table.insert(t, "end_dialog|gacha_cat_view_" .. catID .. "|||\n")
    player:onDialogRequest(table.concat(t))
end

-- ================= SPIN LOGIC =================

-- Pilih hadiah secara acak, tier lebih langka (legend) punya
-- peluang lebih kecil dibanding basic. Lihat TIER_WEIGHT di atas.
local function pickRandomItem(cat)
    local availableTiers = {}
    for _, tier in ipairs(TIER_ORDER) do
        local list = {}
        for _, it in ipairs(cat.items) do
            if it.tier == tier then table.insert(list, it) end
        end
        if #list > 0 then
            table.insert(availableTiers, { tier = tier, weight = TIER_WEIGHT[tier] or 1, items = list })
        end
    end
    if #availableTiers == 0 then return nil end

    local totalWeight = 0
    for _, tg in ipairs(availableTiers) do totalWeight = totalWeight + tg.weight end

    local roll = math.random() * totalWeight
    local cumulative = 0
    local chosen = availableTiers[#availableTiers]
    for _, tg in ipairs(availableTiers) do
        cumulative = cumulative + tg.weight
        if roll <= cumulative then
            chosen = tg
            break
        end
    end

    return chosen.items[math.random(1, #chosen.items)]
end

local function payCost(player, cat, times)
    local itemID = TIER_ITEMS[cat.tier]
    local total = cat.price * times
    if not itemID then return false end
    local have = player:getItemAmount(itemID)
    if have < total then
        player:onAddNotification("interface/large/alert_icon.rttex", "You don't have enough " .. currencyTierName(cat.tier) .. "!", "audio/error.wav", 0)
        return false
    end
    player:changeItem(itemID, -total, 0)
    return true
end

-- Animasi spin: teks "Arrow >> Nama : Jumlah" berganti-ganti makin
-- lambat, lalu berhenti tepat di finalReward (hadiah sebenarnya).
local function runSpinAnimation(player, catID, cat, finalReward, onDone)
    local delays = {80, 100, 130, 170, 220, 280, 350, 450, 600, 800}
    local step = 0
    local color = getCategoryColor(catID)

    local function renderFrame(item)
        local text = itemDisplayName(item.id) .. " : " .. item.amount
        local t = {}
        table.insert(t, "set_default_color|\n")
        table.insert(t, "add_label_with_icon|big|`o" .. cat.name .. "|left|" .. TITLE_ICON .. "|\n")
        table.insert(t, "add_spacer|small|\n")
        table.insert(t, "add_label_with_icon|small|" .. color .. ">> `w" .. text .. "|left|" .. ARROW_ICON .. "|\n")
        table.insert(t, "add_spacer|small|\n")
        -- Tombol Close SELALU ada di setiap frame (bukan cuma di akhir),
        -- supaya kalau macet di frame manapun, player tetap bisa keluar.
        table.insert(t, "add_button|gacha_spin_close_" .. catID .. "|`4[ Close ]|noflags|0|0|\n")
        table.insert(t, "end_dialog|gacha_spinning_" .. catID .. "|||\n")
        player:onDialogRequest(table.concat(t))
    end

    local function spinStep()
        step = step + 1
        if step >= #delays then
            renderFrame(finalReward)
            timer.setTimeout(delays[#delays] / 1000, onDone)
        else
            local randomItem = cat.items[math.random(1, #cat.items)]
            renderFrame(randomItem)
            timer.setTimeout(delays[step] / 1000, spinStep)
        end
    end

    spinStep()
end

local function finishSpinMultiple(player, catID, cat, times)
    local results = {}
    for i = 1, times do
        local reward = pickRandomItem(cat)
        if reward then
            player:changeItem(reward.id, reward.amount, 0)
            table.insert(results, itemDisplayName(reward.id) .. " : " .. reward.amount)
        end
    end

    for _, text in ipairs(results) do
        player:onAddNotification("interface/large/gacha_icon.rttex", "You Got # " .. text, "audio/reward.wav", 0)
    end

    timer.setTimeout(0.5, function()
        showCategory(player, catID)
    end)
end

local function handlePlay(player, catID, times)
    local cat = gachaData.categories[catID]
    if not cat then return end
    if #cat.items == 0 then
        player:onAddNotification("interface/large/alert_icon.rttex", "This gacha has no items configured yet!", "audio/error.wav", 0)
        return
    end
    if not payCost(player, cat, times) then return end

    if times == 1 then
        local finalReward = pickRandomItem(cat)
        runSpinAnimation(player, catID, cat, finalReward, function()
            player:changeItem(finalReward.id, finalReward.amount, 0)
            player:onAddNotification("interface/large/gacha_icon.rttex", "You Got # " .. itemDisplayName(finalReward.id) .. " : " .. finalReward.amount, "audio/reward.wav", 0)
            timer.setTimeout(0.5, function()
                showCategory(player, catID)
            end)
        end)
    else
        finishSpinMultiple(player, catID, cat, times)
    end
end

-- ================= ADMIN: /panelgacha =================

local function showPanelMain(player, msg)
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label_with_icon|big|`oGacha Panel|left|" .. TITLE_ICON .. "|\n")
    table.insert(t, "add_spacer|small|\n")
    if msg ~= nil and msg ~= "" then
        table.insert(t, "add_label|small|" .. msg .. "|left|\n")
        table.insert(t, "add_spacer|small|\n")
    end
    table.insert(t, "add_button|panel_editgacha|[ Edit Gacha ]|noflags|0|0|\n")
    table.insert(t, "add_button|panel_editcategory|[ Edit Category ]|noflags|0|0|\n")
    table.insert(t, "add_button|panel_addcategory|[ Added More Category ]|noflags|0|0|\n")
    table.insert(t, "add_button|panel_changeprice|[ Change Price ]|noflags|0|0|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_close|`4Close|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_main|||\n")
    player:onDialogRequest(table.concat(t))
end

local function showCategoryPickList(player, prefix, title, dialogName)
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`o" .. title .. "|left|\n")
    table.insert(t, "add_spacer|small|\n")
    for _, id in ipairs(gachaData.order) do
        local cat = gachaData.categories[id]
        if cat then
            table.insert(t, "add_button|" .. prefix .. id .. "|" .. cat.name .. "|noflags|0|0|\n")
        end
    end
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_main_back|`wBack|noflags|0|0|\n")
    table.insert(t, "end_dialog|" .. dialogName .. "|||\n")
    player:onDialogRequest(table.concat(t))
end

-- ---- Edit Gacha: pilih kategori -> list item (edit/delete per item) ----

local function showEditGachaList(player)
    showCategoryPickList(player, "panel_editgacha_", "Edit Gacha - Select Category", "panel_editgacha_list")
end

local function showEditGachaItems(player, catID, msg)
    local cat = gachaData.categories[catID]
    if not cat then return end

    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`o" .. cat.name .. "|left|\n")
    table.insert(t, "add_spacer|small|\n")
    if msg ~= nil and msg ~= "" then
        table.insert(t, "add_label|small|" .. msg .. "|left|\n")
        table.insert(t, "add_spacer|small|\n")
    end

    if #cat.items == 0 then
        table.insert(t, "add_label|small|`oNo items yet. Add one below.|left|\n")
        table.insert(t, "add_spacer|small|\n")
    else
        for i, it in ipairs(cat.items) do
            table.insert(t, "add_label|small|" .. TIER_COLOR[it.tier] .. "[" .. TIER_LABEL[it.tier] .. "] `o" .. itemDisplayName(it.id) .. " : " .. it.amount .. "|left|\n")
            table.insert(t, "add_button|item_edit_" .. catID .. "_" .. i .. "|Edit|noflags|0|0|\n")
            table.insert(t, "add_button|item_delete_" .. catID .. "_" .. i .. "|Delete|noflags|0|0|\n")
            table.insert(t, "add_spacer|small|\n")
        end
    end

    table.insert(t, "add_button|additem_" .. catID .. "|`2+ Add New Item|noflags|0|0|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_editgacha_back|`wBack|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_editgacha_items_" .. catID .. "|||\n")
    player:onDialogRequest(table.concat(t))
end

local function showEditItemForm(player, catID, itemIndex)
    local cat = gachaData.categories[catID]
    if not cat then return end
    local it = cat.items[itemIndex]
    if not it then return end

    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`oEdit Item|left|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_label|small|`oCurrent: " .. itemDisplayName(it.id) .. " (" .. TIER_LABEL[it.tier] .. ", x" .. it.amount .. ")|left|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_text_input|new_item_id|New id items :|" .. it.id .. "|20|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_edititem_back|`wBack|noflags|0|0|\n")
    table.insert(t, "add_button|apply_edititem|`2Apply|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_edititem_form_" .. catID .. "_" .. itemIndex .. "|||\n")
    player:onDialogRequest(table.concat(t))
end

local function showAddItemForm(player, catID)
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`oAdd New Item|left|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_text_input|new_item_id|Id items :||20|\n")
    table.insert(t, "add_text_input|new_item_category|Category :||10|\n")
    table.insert(t, "add_label|small|`9Legend / Rare / Basic|left|\n")
    table.insert(t, "add_text_input|new_item_amount|Amount :|1|10|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_additem_back|`wBack|noflags|0|0|\n")
    table.insert(t, "add_button|apply_additem|`2Apply|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_additem_form_" .. catID .. "|||\n")
    player:onDialogRequest(table.concat(t))
end

-- ---- Edit Category: pilih kategori -> rename / delete ----

local function showEditCategoryList(player, msg)
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`oEdit Category|left|\n")
    table.insert(t, "add_spacer|small|\n")
    if msg ~= nil and msg ~= "" then
        table.insert(t, "add_label|small|" .. msg .. "|left|\n")
        table.insert(t, "add_spacer|small|\n")
    end
    for _, id in ipairs(gachaData.order) do
        local cat = gachaData.categories[id]
        if cat then
            table.insert(t, "add_label|small|`o[ " .. cat.name .. " ]|left|\n")
            table.insert(t, "add_button|panel_editcategory_edit_" .. id .. "|Edits|noflags|0|0|\n")
            table.insert(t, "add_button|panel_editcategory_delete_" .. id .. "|Delete|noflags|0|0|\n")
            table.insert(t, "add_spacer|small|\n")
        end
    end
    table.insert(t, "add_button|panel_main_back|`wBack|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_editcategory_list|||\n")
    player:onDialogRequest(table.concat(t))
end

local function showEditCategoryName(player, catID)
    local cat = gachaData.categories[catID]
    if not cat then return end
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`oEdit: " .. cat.name .. "|left|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_text_input|new_name|New Names :|" .. cat.name .. "|30|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_editcategory_back|`wBack|noflags|0|0|\n")
    table.insert(t, "add_button|apply_editcategory|`2Apply|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_editcategory_edit_dialog_" .. catID .. "|||\n")
    player:onDialogRequest(table.concat(t))
end

-- ---- Add Category ----

local function showAddCategory(player)
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`oCategories|left|\n")
    table.insert(t, "add_spacer|small|\n")
    for _, id in ipairs(gachaData.order) do
        local cat = gachaData.categories[id]
        if cat then
            table.insert(t, "add_label|small|`o[ " .. cat.name .. " ]|left|\n")
        end
    end
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_addcategory_create|[ Create ]|noflags|0|0|\n")
    table.insert(t, "add_button|panel_main_back|`wBack|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_addcategory_list|||\n")
    player:onDialogRequest(table.concat(t))
end

local function showCreateCategory(player)
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`oCreate New Category|left|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_text_input|new_cat_name|Create a new :||30|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_addcategory_back|`wBack|noflags|0|0|\n")
    table.insert(t, "add_button|apply_addcategory|`2Apply|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_addcategory_create_dialog|||\n")
    player:onDialogRequest(table.concat(t))
end

-- ---- Change Price: pilih kategori -> lihat & ubah harga ----

local function showChangePriceList(player)
    showCategoryPickList(player, "panel_changeprice_", "Change Price - Select Category", "panel_changeprice_list")
end

local function showChangePriceDialog(player, catID, msg)
    local cat = gachaData.categories[catID]
    if not cat then return end
    local t = {}
    table.insert(t, "set_default_color|\n")
    table.insert(t, "add_label|big|`o" .. cat.name .. "|left|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_label|small|`oNow the price 1 spin is `w" .. cat.price .. " " .. cat.tier .. "|left|\n")
    if msg ~= nil and msg ~= "" then
        table.insert(t, "add_label|small|" .. msg .. "|left|\n")
    end
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_text_input|new_price|Change The Price :|" .. cat.price .. "|10|\n")
    table.insert(t, "add_text_input|new_tier|What The Tier :|" .. cat.tier .. "|10|\n")
    table.insert(t, "add_label|small|`9wl / dl / bgl|left|\n")
    table.insert(t, "add_spacer|small|\n")
    table.insert(t, "add_button|panel_changeprice_back|`wBack|noflags|0|0|\n")
    table.insert(t, "add_button|apply_changeprice|`2Apply|noflags|0|0|\n")
    table.insert(t, "end_dialog|panel_changeprice_dialog_" .. catID .. "|||\n")
    player:onDialogRequest(table.concat(t))
end

-- ================= COMMANDS =================

onPlayerCommandCallback(function(world, player, fullCommand)
    if not player then return false end

    -- PENTING: fullCommand TERNYATA diawali "/" di host ini (terbukti dari
    -- sf65-1.lua yang sudah jalan: fullCommand:gsub("^/", "")). Versi
    -- sebelumnya salah asumsi tidak ada slash, jadi perbandingan
    -- "gachamenu"/"panelgacha" TIDAK PERNAH cocok -- itu akar masalahnya.
    local cmd = (fullCommand or ""):lower():gsub("^/", ""):match("^%S+") or ""

    if cmd == "gachamenu" then
        if not isDefaultRole(player) then
            print("[Gacha] " .. player:getName() .. " tried /gachamenu but doesn't have Role ID " .. GACHA_MENU_ROLE_ID .. " (their role: " .. tostring(player:getRole() and player:getRole().roleName or "unknown") .. ")")
            player:onConsoleMessage("`4You are not allowed to use this command.`o")
            return true
        end
        showMainMenu(player)
        return true
    end

    if cmd == "panelgacha" then
        if not isOwner(player) then
            print("[Gacha] " .. player:getName() .. " tried /panelgacha but doesn't have Role ID " .. OWNER_ROLE_ID .. " (their role: " .. tostring(player:getRole() and player:getRole().roleName or "unknown") .. ")")
            player:onConsoleMessage("`4You are not allowed to use this command. (Owner Role only)`o")
            return true
        end
        showPanelMain(player)
        return true
    end

    return false
end)

-- ================= DIALOG HANDLING (pola data table) =================

onPlayerDialogCallback(function(world, player, data)
    if not player or type(data) ~= "table" then return false end

    local dlg = data.dialog_name or ""
    local btn = data.buttonClicked or ""

    -- ---------- PLAYER SIDE ----------

    if dlg == "gacha_menu_main" then
        local catID = btn:match("^gacha_cat_(%d+)$")
        if catID then
            showCategory(player, tonumber(catID))
        end
        return true
    end

    local viewCatID = dlg:match("^gacha_cat_view_(%d+)$")
    if viewCatID then
        viewCatID = tonumber(viewCatID)
        if btn == "gacha_menu_back" then
            showMainMenu(player)
            return true
        end
        local playCat, playTimes = btn:match("^gacha_play_(%d+)_(%d+)$")
        if playCat then
            handlePlay(player, tonumber(playCat), tonumber(playTimes))
        end
        return true
    end

    local spinCloseCat = dlg:match("^gacha_spinning_(%d+)$")
    if spinCloseCat then
        spinCloseCat = tonumber(spinCloseCat)
        if btn == "gacha_spin_close_" .. spinCloseCat then
            showCategory(player, spinCloseCat)
        end
        return true
    end

    -- ---------- ADMIN SIDE ----------
    if not isOwner(player) then return true end

    if dlg == "panel_main" then
        if btn == "panel_editgacha" then
            showEditGachaList(player)
        elseif btn == "panel_editcategory" then
            showEditCategoryList(player)
        elseif btn == "panel_addcategory" then
            showAddCategory(player)
        elseif btn == "panel_changeprice" then
            showChangePriceList(player)
        elseif btn == "panel_close" then
            -- Tidak buka dialog baru -> panel otomatis tertutup
        end
        return true
    end

    if btn == "panel_main_back" then
        showPanelMain(player)
        return true
    end

    -- Edit Gacha: pilih kategori
    if dlg == "panel_editgacha_list" then
        local catID = btn:match("^panel_editgacha_(%d+)$")
        if catID then
            showEditGachaItems(player, tonumber(catID))
        end
        return true
    end

    -- Edit Gacha: list item dalam satu kategori
    local itemsListCat = dlg:match("^panel_editgacha_items_(%d+)$")
    if itemsListCat then
        itemsListCat = tonumber(itemsListCat)

        if btn == "panel_editgacha_back" then
            showEditGachaList(player)
            return true
        end

        if btn == "additem_" .. itemsListCat then
            showAddItemForm(player, itemsListCat)
            return true
        end

        local editIdx = btn:match("^item_edit_" .. itemsListCat .. "_(%d+)$")
        if editIdx then
            showEditItemForm(player, itemsListCat, tonumber(editIdx))
            return true
        end

        local delIdx = btn:match("^item_delete_" .. itemsListCat .. "_(%d+)$")
        if delIdx then
            delIdx = tonumber(delIdx)
            local cat = gachaData.categories[itemsListCat]
            if cat and cat.items[delIdx] then
                table.remove(cat.items, delIdx)
                saveGacha()
            end
            showEditGachaItems(player, itemsListCat, "`2Item deleted!")
            return true
        end

        return true
    end

    -- Edit Gacha: form edit satu item
    local editFormCat, editFormIdx = dlg:match("^panel_edititem_form_(%d+)_(%d+)$")
    if editFormCat then
        editFormCat = tonumber(editFormCat)
        editFormIdx = tonumber(editFormIdx)

        if btn == "panel_edititem_back" then
            showEditGachaItems(player, editFormCat)
            return true
        end

        if btn == "apply_edititem" then
            local cat = gachaData.categories[editFormCat]
            local it = cat and cat.items[editFormIdx]
            if it then
                local newID = tonumber(data["new_item_id"])
                if newID then
                    it.id = newID
                    saveGacha()
                end
            end
            showEditGachaItems(player, editFormCat, "`2Item updated!")
            return true
        end

        return true
    end

    -- Edit Gacha: form tambah item baru
    local addFormCat = dlg:match("^panel_additem_form_(%d+)$")
    if addFormCat then
        addFormCat = tonumber(addFormCat)

        if btn == "panel_additem_back" then
            showEditGachaItems(player, addFormCat)
            return true
        end

        if btn == "apply_additem" then
            local cat = gachaData.categories[addFormCat]
            if cat then
                local newID = tonumber(data["new_item_id"])
                local rawTier = string.lower(data["new_item_category"] or "")
                local amount = tonumber(data["new_item_amount"]) or 1

                if not newID then
                    showEditGachaItems(player, addFormCat, "`4Invalid item ID!")
                    return true
                end
                if rawTier ~= "legend" and rawTier ~= "rare" and rawTier ~= "basic" then
                    showEditGachaItems(player, addFormCat, "`4Category must be Legend / Rare / Basic!")
                    return true
                end

                table.insert(cat.items, { id = newID, amount = amount, tier = rawTier })
                saveGacha()
            end
            showEditGachaItems(player, addFormCat, "`2Item added!")
            return true
        end

        return true
    end

    -- Edit Category flow
    if dlg == "panel_editcategory_list" then
        local editID = btn:match("^panel_editcategory_edit_(%d+)$")
        if editID then
            showEditCategoryName(player, tonumber(editID))
            return true
        end
        local delID = btn:match("^panel_editcategory_delete_(%d+)$")
        if delID then
            delID = tonumber(delID)
            gachaData.categories[delID] = nil
            for i, id in ipairs(gachaData.order) do
                if id == delID then
                    table.remove(gachaData.order, i)
                    break
                end
            end
            saveGacha()
            showEditCategoryList(player, "`2Category deleted!")
            return true
        end
        return true
    end

    local renameCat = dlg:match("^panel_editcategory_edit_dialog_(%d+)$")
    if renameCat then
        renameCat = tonumber(renameCat)
        if btn == "panel_editcategory_back" then
            showEditCategoryList(player)
            return true
        end
        if btn == "apply_editcategory" then
            local cat = gachaData.categories[renameCat]
            if cat then
                local newName = data["new_name"]
                if newName and newName ~= "" then
                    cat.name = newName
                    saveGacha()
                end
            end
            showEditCategoryList(player, "`2Saved!")
        end
        return true
    end

    -- Add Category flow
    if dlg == "panel_addcategory_list" then
        if btn == "panel_addcategory_create" then
            showCreateCategory(player)
        end
        return true
    end

    if dlg == "panel_addcategory_create_dialog" then
        if btn == "panel_addcategory_back" then
            showAddCategory(player)
            return true
        end
        if btn == "apply_addcategory" then
            local newName = data["new_cat_name"]
            if newName and newName ~= "" then
                local newID = gachaData.nextID
                gachaData.categories[newID] = {name = newName, price = 1, tier = "bgl", items = {}}
                table.insert(gachaData.order, newID)
                gachaData.nextID = newID + 1
                saveGacha()
            end
            showAddCategory(player)
        end
        return true
    end

    -- Change Price flow
    if dlg == "panel_changeprice_list" then
        local catID = btn:match("^panel_changeprice_(%d+)$")
        if catID then
            showChangePriceDialog(player, tonumber(catID))
        end
        return true
    end

    local priceCat = dlg:match("^panel_changeprice_dialog_(%d+)$")
    if priceCat then
        priceCat = tonumber(priceCat)
        if btn == "panel_changeprice_back" then
            showChangePriceList(player)
            return true
        end
        if btn == "apply_changeprice" then
            local cat = gachaData.categories[priceCat]
            if cat then
                local newPrice = tonumber(data["new_price"])
                local newTier = data["new_tier"]
                if newTier then newTier = string.lower(newTier) end

                if newPrice and newPrice > 0 then
                    cat.price = newPrice
                end
                if newTier == "wl" or newTier == "dl" or newTier == "bgl" then
                    cat.tier = newTier
                end
                saveGacha()
                showChangePriceDialog(player, priceCat, "`2Saved! 1 spin is now " .. cat.price .. " " .. cat.tier .. ".")
                return true
            end
        end
        return true
    end

    return false
end)
