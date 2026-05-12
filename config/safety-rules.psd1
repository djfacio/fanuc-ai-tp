@{
    BlockedPatterns = @(
        @{
            Rule = "SystemVariable"
            Pattern = '\$[A-Za-z0-9_]+'
            Message = "System variable references are blocked unless explicitly reviewed."
        }
        @{
            Rule = "Dcs"
            Pattern = '\bDCS\b'
            Message = "DCS references are blocked unless explicitly reviewed."
        }
        @{
            Rule = "Karel"
            Pattern = '\bKAREL\b'
            Message = "KAREL references are blocked unless explicitly reviewed."
        }
        @{
            Rule = "Run"
            Pattern = '\bRUN\b'
            Message = "RUN behavior is blocked unless explicitly reviewed."
        }
        @{
            Rule = "Abort"
            Pattern = '\bABORT\b'
            Message = "ABORT behavior is blocked unless explicitly reviewed."
        }
        @{
            Rule = "Uop"
            Pattern = '\bUOP\b'
            Message = "UOP references are blocked unless explicitly reviewed."
        }
        @{
            Rule = "ProductionCall"
            Pattern = '\bCALL\s+F_MAIN\b'
            Message = "Calls into production entry programs are blocked unless explicitly reviewed."
        }
    )
}
