--!strict
-- ModuleScript: ReplicatedStorage.Config.EconomyConfig

local Constants = require(script.Parent.Constants)

local EconomyConfig = {}

EconomyConfig.CURRENCIES = { "mon", "silver", "ryo" } :: { string }

-- How many units of fromCurrency = 1 unit of toCurrency
EconomyConfig.EXCHANGE_RATES = {
	mon    = { silver = 250,  ryo = 4000 },
	silver = { ryo = 16,     mon = 250  },  -- breakdown: 1 silver = 250 mon
	ryo    = { silver = 16,  mon = 4000 },  -- breakdown: 1 ryo = 4000 mon
} :: { [string]: { [string]: number } }

-- Default exchange target per source (used by RequestExchange remote)
EconomyConfig.DEFAULT_EXCHANGE_TARGET = {
	mon    = "silver",  -- upgrade
	silver = "ryo",    -- upgrade
	ryo    = "mon",    -- break down
} :: { [string]: string }

EconomyConfig.CHANGER_FEE     = 0.05   -- 5% of output destroyed (gold sink)
EconomyConfig.MAX_MON         = Constants.MAX_MON  -- reference foundation
EconomyConfig.TRANSACTION_RATE = 5     -- remote calls/sec for economy events

EconomyConfig.MONEY_CHANGER_TAG = "MoneyChanger"
EconomyConfig.MONEY_CHANGER_PROMPT_NAME = "MoneyChangerPrompt"
EconomyConfig.MONEY_CHANGER_RANGE = 14
EconomyConfig.MONEY_CHANGER_FALLBACK_IN_STUDIO = true

return EconomyConfig
