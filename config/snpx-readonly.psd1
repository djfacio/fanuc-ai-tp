@{
    SchemaVersion = 1
    Enabled = $false
    Protocol = "SNPX_V2"
    MappingMode = "per-connection"
    RobotIp = "192.168.5.10"
    Port = 60008
    Notes = "Read-only SNPX V2 plan. Addresses are project-owned per-connection ASG projections, not raw FANUC native addresses."

    AddressAssignment = @{
        Mode = "project-owned-asg"
        Area = "%R"
        Start = 5
        SlotLimit = 80
        Handshake = @(
            "Connect to FANUC SNPX endpoint on TCP 60008",
            'Probe $SNPX_PARAM.$VERSION',
            'Probe $SNPX_PARAM.$NUM_CIMP',
            "CLRASG to create a private per-connection assignment table",
            "SETASG each read below into the configured %R projection window",
            'Read back $SNPX_ASG entries and fail closed if any assignment differs'
        )
        Notes = "Live code must program these assignments after connect. Unassigned %R reads can return 0, so readback verification is mandatory."
    }

    SystemProbes = @(
        @{
            Name = "SNPX version probe"
            SetAsgRegion = '$SNPX_PARAM.$VERSION'
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxStart = 1
            SnpxAddress = "%R00001"
            WordCount = 2
            RequireNonZero = $true
        },
        @{
            Name = "SNPX multi-connection probe"
            SetAsgRegion = '$SNPX_PARAM.$NUM_CIMP'
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxStart = 3
            SnpxAddress = "%R00003"
            WordCount = 2
            RequireNonZero = $false
        }
    )

    Reads = @(
        @{
            Name = "AI_REGDIAG marker A"
            Fanuc = "R[90]"
            SnapshotKey = "R[90]"
            Type = "int"
            Representation = "word"
            AsgSlot = 1
            SetAsgRegion = "R[90]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 5
            SnpxAddress = "%R00005"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "AI_REGDIAG marker B"
            Fanuc = "R[91]"
            SnapshotKey = "R[91]"
            Type = "int"
            Representation = "word"
            AsgSlot = 2
            SetAsgRegion = "R[91]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 7
            SnpxAddress = "%R00007"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "AI_CELLCHK marker"
            Fanuc = "R[97]"
            SnapshotKey = "R[97]"
            Type = "int"
            Representation = "word"
            AsgSlot = 3
            SetAsgRegion = "R[97]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 9
            SnpxAddress = "%R00009"
            WordCount = 2
            Required = $true
        },
        @{
            Name = "AI_SNAPSHOT marker"
            Fanuc = "R[98]"
            SnapshotKey = "R[98]"
            Type = "int"
            Representation = "word"
            AsgSlot = 4
            SetAsgRegion = "R[98]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 11
            SnpxAddress = "%R00011"
            WordCount = 2
            Required = $true
        },
        @{
            Name = "AI_HELLO marker"
            Fanuc = "R[99]"
            SnapshotKey = "R[99]"
            Type = "int"
            Representation = "word"
            AsgSlot = 5
            SetAsgRegion = "R[99]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 13
            SnpxAddress = "%R00013"
            WordCount = 2
            Required = $true
        },
        @{
            Name = "AI_IODIAG reviewed pulse output"
            Fanuc = "DO[1]"
            SnapshotKey = "DO[1]"
            Type = "bool"
            Representation = "word-bool"
            AsgSlot = 6
            SetAsgRegion = "DO[1]"
            SetAsgDataType = "BOOLEAN"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 15
            SnpxAddress = "%R00015"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "Production sample output"
            Fanuc = "DO[107]"
            SnapshotKey = "DO[107]"
            Type = "bool"
            Representation = "word-bool"
            AsgSlot = 7
            SetAsgRegion = "DO[107]"
            SetAsgDataType = "BOOLEAN"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 17
            SnpxAddress = "%R00017"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "Production sample output"
            Fanuc = "DO[110]"
            SnapshotKey = "DO[110]"
            Type = "bool"
            Representation = "word-bool"
            AsgSlot = 8
            SetAsgRegion = "DO[110]"
            SetAsgDataType = "BOOLEAN"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 19
            SnpxAddress = "%R00019"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "Production sample output"
            Fanuc = "DO[113]"
            SnapshotKey = "DO[113]"
            Type = "bool"
            Representation = "word-bool"
            AsgSlot = 9
            SetAsgRegion = "DO[113]"
            SetAsgDataType = "BOOLEAN"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 21
            SnpxAddress = "%R00021"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "Production sample register"
            Fanuc = "R[103]"
            SnapshotKey = "R[103]"
            Type = "int"
            Representation = "word"
            AsgSlot = 10
            SetAsgRegion = "R[103]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 23
            SnpxAddress = "%R00023"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "Production sample register"
            Fanuc = "R[107]"
            SnapshotKey = "R[107]"
            Type = "int"
            Representation = "word"
            AsgSlot = 11
            SetAsgRegion = "R[107]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 25
            SnpxAddress = "%R00025"
            WordCount = 2
            Required = $false
        },
        @{
            Name = "Production sample register"
            Fanuc = "R[110]"
            SnapshotKey = "R[110]"
            Type = "int"
            Representation = "word"
            AsgSlot = 12
            SetAsgRegion = "R[110]"
            SetAsgDataType = "INTEGER"
            SetAsgMultiply = 1
            SnpxArea = "%R"
            SnpxStart = 27
            SnpxAddress = "%R00027"
            WordCount = 2
            Required = $false
        }
    )
}
