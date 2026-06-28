--!strict
-- ModuleScript: ReplicatedStorage.Packages.ProfileStore
-- VENDOR STUB — replace with loleris/ProfileStore for production.
-- Real library: https://github.com/MadStudioRoblox/ProfileStore
-- This stub has the same API surface but lacks session locking,
-- retry logic, and robust DataStore error handling.

local DataStoreService = game:GetService("DataStoreService")

-- ── Signal ────────────────────────────────────────────────────────────────────

type Signal = {
	Connect: (self: Signal, fn: () -> ()) -> (),
	_fire:   (self: Signal) -> (),
}

local function newSignal(): Signal
	local fns: { () -> () } = {}
	local s = {} :: Signal
	s.Connect = function(self, fn) table.insert(fns, fn) end
	s._fire   = function(self)
		for _, fn in fns do pcall(fn) end
	end
	return s
end

-- ── Profile type ──────────────────────────────────────────────────────────────

export type Profile = {
	Data:         { [string]: any },
	OnSessionEnd: Signal,
	IsActive:     (self: Profile) -> boolean,
	Save:         (self: Profile) -> (),
	EndSession:   (self: Profile) -> (),
}

-- ── Store ─────────────────────────────────────────────────────────────────────

type StorePrivate = {
	_ds:       DataStore,
	_template: { [string]: any },
}

local StoreClass: any = {}
StoreClass.__index = StoreClass

export type ProfileStore = typeof(setmetatable({} :: StorePrivate, StoreClass))

local ProfileStoreMod = {}

function ProfileStoreMod.New(storeName: string, template: { [string]: any }): ProfileStore
	local ds = DataStoreService:GetDataStore(storeName)
	return setmetatable({ _ds = ds, _template = template } :: StorePrivate, StoreClass) :: any
end

function StoreClass:StartSessionAsync(key: string, _settings: any?): Profile?
	local self = self :: StorePrivate
	local rawData: { [string]: any }?
	local ok, err = pcall(function()
		rawData = self._ds:GetAsync(key) :: any
	end)
	if not ok then
		warn("[ProfileStore] GetAsync failed for " .. key .. ": " .. tostring(err))
		return nil
	end

	local data: { [string]: any } = {}
	if rawData ~= nil then
		for k, v in rawData :: { [string]: any } do data[k] = v end
	else
		for k, v in self._template do data[k] = v end
		data.createdAt = os.time()
	end

	-- Reconcile keys added to the template since profile was created
	for k, v in self._template do
		if data[k] == nil then data[k] = v end
	end

	local active     = true
	local sessionEnd = newSignal()
	local ds         = self._ds

	local profile: Profile = {
		Data         = data,
		OnSessionEnd = sessionEnd,
		IsActive = function(self2) return active end,
		Save = function(self2)
			if not active then return end
			local saveOk, saveErr = pcall(function()
				ds:SetAsync(key, self2.Data)
			end)
			if not saveOk then
				warn("[ProfileStore] SetAsync failed for " .. key .. ": " .. tostring(saveErr))
			end
		end,
		EndSession = function(self2)
			if not active then return end
			active = false
			self2:Save()
			sessionEnd:_fire()
		end,
	}
	return profile
end

return ProfileStoreMod
