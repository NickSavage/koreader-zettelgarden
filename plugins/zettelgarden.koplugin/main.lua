local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local DictQuickLookup = require("ui/widget/dictquicklookup")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local http = require("socket.http")
local JSON = require("json")
local logger = require("logger")
local socket = require("socket")
local socketutil = require("socketutil")
local ltn12 = require("ltn12")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Zettelgarden = WidgetContainer:extend{
    name = "zettelgarden",
    is_doc_only = false,
}

function Zettelgarden:init()
    -- Store instance for access from other modules
    Zettelgarden.instance = self

    self.token_expiry = 0
    self.ui.menu:registerToMainMenu(self)
    self.zg_settings = self:readSettings()

    -- Load settings with defaults
    self.server_url = self.zg_settings:readSetting("server_url")
    self.email = self.zg_settings:readSetting("email")
    self.password = self.zg_settings:readSetting("password")

    -- Add Zettelgarden to the highlight menu
    if self.ui.highlight then
        self.ui.highlight:addToHighlightDialog("zettelgarden", function(this)
            return {
                text = _("Send to Zettelgarden"),
                callback = function()
                    self:saveHighlightAndSend(this.selected_text.text, this)
                    this:onClose()
                end,
            }
        end)
    end

    if Device:hasKeyboard() then
        self.key_events = {
            ShowZettelgardenLookup = { { "Alt", "Z" } },
        }
    end
end

function Zettelgarden:addToMainMenu(menu_items)
    menu_items.zettelgarden = {
        text = _("Zettelgarden"),
        sub_item_table = {
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Configure Zettelgarden server"),
                        keep_menu_open = true,
                        callback = function()
                            self:editServerSettings()
                        end,
                    },
                },
            },
        },
    }
end

function Zettelgarden:editServerSettings()
    self.settings_dialog = MultiInputDialog:new{
        title = _("Zettelgarden settings"),
        fields = {
            {
                text = self.server_url or "",
                hint = _("Server URL"),
            },
            {
                text = self.email or "",
                hint = _("Email"),
            },
            {
                text = self.password or "",
                text_type = "password",
                hint = _("Password"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.settings_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = self.settings_dialog:getFields()
                        self.server_url = fields[1]
                        self.email = fields[2]
                        self.password = fields[3]
                        self:saveSettings()
                        UIManager:close(self.settings_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function Zettelgarden:getBearerToken()
    -- Check if settings are configured
    if not self.server_url or not self.email or not self.password then
        UIManager:show(InfoMessage:new{
            text = T(_([[Server settings incomplete.
URL: %1
Email: %2
Password: %3]]),
                self.server_url or "not set",
                self.email or "not set",
                self.password and "set" or "not set"
            ),
        })
        return false
    end

    -- Check if token is still valid
    local now = os.time()
    if self.token_expiry - now > 300 then
        return true
    end

    -- Make login API call to get new token
    local login_url = self.server_url .. "/api/login"
    local body = {
        email = self.email,
        password = self.password,
    }
    local body_json = JSON.encode(body)

    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json",
        ["Content-Length"] = tostring(#body_json),
    }

    local ok, result, err_code = self:callAPI("POST", login_url, headers, body_json)
    if ok then
        self.access_token = result.access_token
        self.token_expiry = now + (24 * 60 * 60)
        return true
    else
        local debug_info = T(_([[Login failed!
URL: %1
Error type: %2
Error code: %3
Response: %4]]),
            login_url,
            result,
            err_code or "none",
            self.last_response or "no response"
        )

        UIManager:show(InfoMessage:new{
            text = debug_info,
        })
        return false
    end
end

function Zettelgarden:callAPI(method, url, headers, body)
    local sink = {}
    local request = {
        url = url,
        method = method,
        headers = headers,
        sink = ltn12.sink.table(sink),
    }

    if body then
        request.source = ltn12.source.string(body)
    end

    local code, headers, status = socket.skip(1, http.request(request))

    if headers == nil then
        self.last_response = T("Network error: %1", status)
        return false, "network_error"
    end

    local content = table.concat(sink)
    self.last_response = content -- Save response for error reporting

    if code == 200 then
        if content ~= "" then
            local ok, result = pcall(JSON.decode, content)
            if ok and result then
                return true, result
            end
            return false, "json_error"
        end
        return false, "empty_response"
    end

    return false, "http_error", code
end

function Zettelgarden:createCardFromSelection(text)
    if not text then
        UIManager:show(InfoMessage:new{
            text = _("No text selected. Please select some text first."),
        })
        return
    end

    -- Clean up the selected text
    text = util.cleanupSelectedText(text)

    local connect_callback = function()
        if self:getBearerToken() then
            -- Show dialog to get card details
            self.card_dialog = MultiInputDialog:new{
                title = _("Create new Zettelgarden card"),
                fields = {
                    {
                        text = "",
                        hint = _("Card ID (optional)"),
                    },
                    {
                        text = "",
                        hint = _("Title (optional)"),
                    },
                    {
                        text = text,
                        hint = _("Selected text"),
                        text_type = "text",
                        readonly = true,
                    },
                },
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(self.card_dialog)
                            end,
                        },
                        {
                            text = _("Create"),
                            callback = function()
                                local fields = self.card_dialog:getFields()
                                self:saveCard(fields[1], fields[2], text)
                                UIManager:close(self.card_dialog)
                            end,
                        },
                    },
                },
            }
            UIManager:show(self.card_dialog)
            self.card_dialog:onShowKeyboard()
        end
    end
    NetworkMgr:runWhenOnline(connect_callback)
end

function Zettelgarden:saveCard(card_id, title, body)
    local connect_callback = function()
        -- Always try to get a token if we don't have one
        if not self.access_token then
            if not self:getBearerToken() then
                return  -- getBearerToken will show its own error message
            end
        end

        local card = {
            card_id = card_id,
            title = title,
            body = body,
        }

        local headers = {
            ["Content-type"] = "application/json",
            ["Accept"] = "application/json",
            ["Authorization"] = "Bearer " .. self.access_token,
        }

        local url = self.server_url .. "/api/cards"
        local ok, result = self:callAPI("POST", url, headers, JSON.encode(card))

        if ok then
            UIManager:show(InfoMessage:new{
                text = _("Card created successfully."),
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("Failed to create card."),
            })
        end
    end
    NetworkMgr:runWhenOnline(connect_callback)
end

function Zettelgarden:readSettings()
    local zg_settings = LuaSettings:open(DataStorage:getSettingsDir().."/zettelgarden.lua")
    return zg_settings
end

function Zettelgarden:saveSettings()
    self.zg_settings:saveSetting("server_url", self.server_url)
    self.zg_settings:saveSetting("email", self.email)
    self.zg_settings:saveSetting("password", self.password)
    self.zg_settings:flush()
end

function Zettelgarden:saveHighlightAndSend(text, ui_highlight)
    -- First save the highlight
    local highlight_index = ui_highlight:saveHighlight(true)

    -- Then send to Zettelgarden
    self:createCardFromSelection(text)

    return highlight_index
end

return Zettelgarden 