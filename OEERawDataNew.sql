USE [OLTPDB]
GO
/****** Object:  UserDefinedFunction [OLTPSCHEMA].[sswFuncOEERawData]    Script Date: 1/12/2023 3:10:18 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER FUNCTION [OLTPSCHEMA].[sswFuncOEERawData]
(
	@Factory AS NVARCHAR(60)
    --, @ResourceFamily AS NVARCHAR(60)         
	, @ResourceGroup AS NVARCHAR(600)
    --, @ResourceType AS NVARCHAR(60)
    , @Resource AS NVARCHAR(600)
    , @FromDate AS DATETIME
    , @ToDate AS DATETIME
	, @IgnoreNonScheduledTime AS BIT -- OEE Details Portal Page ignores the Non-Scheduled Time
)
RETURNS TABLE
AS
RETURN
WITH Resources AS
(
    SELECT DISTINCT
        R.ResourceName Resource
        , R.ResourceId
		, R.Description Description
		, R.sswIdealCycleTime
        --, RF.ResourceFamilyName ResourceFamily
		--, RT.ResourceTypeName ResourceType
		, F.FactoryName Factory
		, PS.Availability ResourceAvailability
		, RSC.ResourceStatusCodeName ResourceStatusCode
		, RSR.ResourceStatusReasonName ResourceStatusReason
		, CASE WHEN RSC.isOEELossCategory = 1 THEN 'Availability'
			   WHEN RSC.isOEELossCategory = 2 THEN 'Performance'
			   WHEN RSC.isOEELossCategory = 3 THEN 'Schedule'
			   ELSE '' END OEELossCategory

        , CAST(CASE WHEN @FromDate >= GETDATE() OR PS.LastStatusChangeDate IS NULL OR PS.LastStatusChangeDate > @ToDate OR PS.Availability = 1 THEN 0
               WHEN PS.LastStatusChangeDate < @FromDate AND @ToDate > GETDATE() THEN DATEDIFF(SECOND, @FromDate, GETDATE())
               WHEN PS.LastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, @ToDate)
               WHEN @ToDate > GETDATE() THEN DATEDIFF(SECOND, PS.LastStatusChangeDate, GETDATE())
               ELSE DATEDIFF(SECOND, PS.LastStatusChangeDate, @ToDate) END AS FLOAT) CurrentDowntimeInSecs

        , CAST (CASE WHEN @FromDate >= GETDATE() OR PS.LastStatusChangeDate IS NULL OR PS.LastStatusChangeDate > @ToDate OR PS.Availability = 1 OR ISNULL(RSC.isOEELossCategory, 0) <> 3 THEN 0
               WHEN PS.LastStatusChangeDate < @FromDate AND @ToDate > GETDATE() THEN DATEDIFF(SECOND, @FromDate, GETDATE())
               WHEN PS.LastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, @ToDate)
               WHEN @ToDate > GETDATE() THEN DATEDIFF(SECOND, PS.LastStatusChangeDate, GETDATE())
               ELSE DATEDIFF(SECOND, PS.LastStatusChangeDate, @ToDate) END AS FLOAT) CurrentScheduledDowntimeInSecs

        --, CAST(CASE WHEN @FromDate >= GETDATE() OR PS.LastStatusChangeDate IS NULL OR PS.LastStatusChangeDate > @ToDate OR PS.Availability = 1 OR ISNULL(RSC.isOEELossCategory, 1) <> 1 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
               --WHEN PS.LastStatusChangeDate < @FromDate AND @ToDate > GETDATE() THEN DATEDIFF(SECOND, @FromDate, GETDATE())
               --WHEN PS.LastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, @ToDate)
               --WHEN @ToDate > GETDATE() THEN DATEDIFF(SECOND, PS.LastStatusChangeDate, GETDATE())
               --ELSE DATEDIFF(SECOND, PS.LastStatusChangeDate, @ToDate) END AS FLOAT) CurrentUnscheduledDowntimeInSecs

		, CAST(CASE WHEN @FromDate >= GETDATE() OR PS.LastStatusChangeDate IS NULL OR PS.LastStatusChangeDate > @ToDate OR PS.Availability = 1 OR ISNULL(RSC.isOEELossCategory, 1) <> 1 OR ISNULL(RSC.ResourceState,0)<>7 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
               WHEN PS.LastStatusChangeDate < @FromDate AND @ToDate > GETDATE() THEN DATEDIFF(SECOND, @FromDate, GETDATE())
               WHEN PS.LastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, @ToDate)
               WHEN @ToDate > GETDATE() THEN DATEDIFF(SECOND, PS.LastStatusChangeDate, GETDATE())
               ELSE DATEDIFF(SECOND, PS.LastStatusChangeDate, @ToDate) END AS FLOAT) CurrentEquipmentDowntimeInSecs

		, CAST(CASE WHEN @FromDate >= GETDATE() OR PS.LastStatusChangeDate IS NULL OR PS.LastStatusChangeDate > @ToDate OR PS.Availability = 1 OR ISNULL(RSC.isOEELossCategory, 1) <> 1 OR ISNULL(RSC.ResourceState,0)<>9 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
               WHEN PS.LastStatusChangeDate < @FromDate AND @ToDate > GETDATE() THEN DATEDIFF(SECOND, @FromDate, GETDATE())
               WHEN PS.LastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, @ToDate)
               WHEN @ToDate > GETDATE() THEN DATEDIFF(SECOND, PS.LastStatusChangeDate, GETDATE())
               ELSE DATEDIFF(SECOND, PS.LastStatusChangeDate, @ToDate) END AS FLOAT) CurrentInternalDowntimeInSecs

		, CAST(CASE WHEN @FromDate >= GETDATE() OR PS.LastStatusChangeDate IS NULL OR PS.LastStatusChangeDate > @ToDate OR PS.Availability = 1 OR ISNULL(RSC.isOEELossCategory, 1) <> 1 OR ISNULL(RSC.ResourceState,0)<>10 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
               WHEN PS.LastStatusChangeDate < @FromDate AND @ToDate > GETDATE() THEN DATEDIFF(SECOND, @FromDate, GETDATE())
               WHEN PS.LastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, @ToDate)
               WHEN @ToDate > GETDATE() THEN DATEDIFF(SECOND, PS.LastStatusChangeDate, GETDATE())
               ELSE DATEDIFF(SECOND, PS.LastStatusChangeDate, @ToDate) END AS FLOAT) CurrentExternalDowntimeInSecs

        , CD.CDOName ResourceCDOType
        , CAST(DATEDIFF(SECOND, @FromDate, @ToDate) AS FLOAT) DurationInSecs
    FROM
        ResourceDef R
        INNER JOIN CDODefinition CD ON R.CDOTypeId = CD.CDODefId
        INNER JOIN ProductionStatus PS ON R.ProductionStatusId = PS.ProductionStatusId
		LEFT OUTER JOIN ResourceGroupEntries RGE ON R.ResourceId = RGE.EntriesId
		LEFT OUTER JOIN ResourceGroup RG ON RGE.ResourceGroupId = RG.ResourceGroupId
		LEFT OUTER JOIN Factory F ON R.FactoryId = F.FactoryId
        --LEFT OUTER JOIN ResourceFamily RF ON R.ResourceFamilyId = RF.ResourceFamilyId
		--LEFT OUTER JOIN ResourceType RT ON R.ResourceTypeId = RT.ResourceTypeId
		LEFT OUTER JOIN ResourceStatusCode RSC ON PS.StatusId = RSC.ResourceStatusCodeId
		LEFT OUTER JOIN ResourceStatusReason RSR ON PS.ReasonId = RSR.ResourceStatusReasonId
    WHERE
        (ISNULL(@Factory, '%') = '%' OR ISNULL(F.FactoryName, '%') LIKE @Factory)
        --AND (ISNULL(@ResourceFamily, '%') = '%' OR ISNULL(RF.ResourceFamilyName, '%') LIKE @ResourceFamily)
		--AND R.ResourceName NOT LIKE 'ARIEL_CARRIER%' AND R.ResourceName NOT LIKE 'MINIME_CARRIER%'
        --AND (ISNULL(@ResourceType, '%') = '%' OR ISNULL(RT.ResourceTypeName, '%') LIKE @ResourceType)
        AND (ISNULL(@Resource, '%') = '%' OR R.ResourceName IN (SELECT value FROM string_split(@Resource,',')))
		AND (ISNULL(@ResourceGroup, '%') = '%' OR RG.ResourceGroupName IN (SELECT value FROM string_split(@ResourceGroup,','))) --ISNULL(RG.ResourceGroupName, '%') LIKE @ResourceGroup)
        AND R.isIncludeInOEE = 1
)
, HistoryDowntimes AS
(
    SELECT
        RSH.HistoryId ResourceId
		--, CAST(SUM(CASE WHEN RSC.ResourceState = 1 AND RSH.LastStatusChangeDate <= @ToDate THEN 1 ELSE 0 END) AS FLOAT) HistoryCountNonscheduledTime
		--, CAST(SUM(CASE WHEN (RSC.ResourceState = 9 OR RSC.ResourceState = 10) AND RSH.LastStatusChangeDate <= @ToDate THEN 1 ELSE 0 END) AS FLOAT) HistoryCountUnscheduledDowntime
		--, CAST(SUM(CASE WHEN RSC.ResourceState = 3 AND RSH.LastStatusChangeDate <= @ToDate THEN 1 ELSE 0 END) AS FLOAT) HistoryCountScheduledDowntime
		--, CAST(SUM(CASE WHEN RSC.ResourceState = 4 AND RSH.LastStatusChangeDate <= @ToDate THEN 1 ELSE 0 END) AS FLOAT) HistoryCountEngineeringTime
		--, CAST(SUM(CASE WHEN RSC.ResourceState = 5 AND RSH.LastStatusChangeDate <= @ToDate THEN 1 ELSE 0 END) AS FLOAT) HistoryCountProductiveTime
		--, CAST(SUM(CASE WHEN RSC.ResourceState = 6 AND RSH.LastStatusChangeDate <= @ToDate THEN 1 ELSE 0 END) AS FLOAT) HistoryCountStandbyTime
		--, CAST(SUM(CASE WHEN RSC.ResourceState = 7 AND RSH.LastStatusChangeDate <= @ToDate THEN 1 ELSE 0 END) AS FLOAT) HistoryCountMachineDowntime

        , CAST(SUM(CASE WHEN RSH.OldAvailability = 1 THEN 0
                   WHEN RSH.OldLastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, RSH.LastStatusChangeDate)
				   WHEN RSH.LastStatusChangeDate >= @ToDate THEN DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, ISNULL(@ToDate,GETDATE()))
                   ELSE DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, RSH.LastStatusChangeDate) END) AS FLOAT) HistoryDowntimeInSecs

        , CAST(SUM(CASE WHEN RSH.OldAvailability = 1 OR ISNULL(ORSC.isOEELossCategory, 0) <> 3 THEN 0
                   WHEN RSH.OldLastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, RSH.LastStatusChangeDate)
				   WHEN RSH.LastStatusChangeDate >= @ToDate THEN DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, ISNULL(@ToDate,GETDATE()))
                   ELSE DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, RSH.LastStatusChangeDate) END) AS FLOAT) HistoryScheduledDowntimeInSecs

        --, CAST(SUM(CASE WHEN RSH.OldAvailability = 1 OR ISNULL(ORSC.isOEELossCategory, 1) <> 1 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
                   --WHEN RSH.OldLastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, RSH.LastStatusChangeDate)
				   --WHEN RSH.LastStatusChangeDate >= @ToDate THEN DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, ISNULL(@ToDate,GETDATE()))
                   --ELSE DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, RSH.LastStatusChangeDate) END) AS FLOAT) HistoryUnscheduledDowntimeInSecs

		, CAST(SUM(CASE WHEN RSH.OldAvailability = 1 OR ISNULL(ORSC.isOEELossCategory, 1) <> 1 OR ISNULL(RSH.OldResourceState,0) <> 7 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
                   WHEN RSH.OldLastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, RSH.LastStatusChangeDate)
				   WHEN RSH.LastStatusChangeDate >= @ToDate THEN DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, ISNULL(@ToDate,GETDATE()))
                   ELSE DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, RSH.LastStatusChangeDate) END) AS FLOAT) HistoryEquipmentDowntimeInSecs
		, CAST(SUM(CASE WHEN RSH.OldAvailability = 1 OR ISNULL(ORSC.isOEELossCategory, 1) <> 1 OR ISNULL(RSH.OldResourceState,0) <> 9 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
                   WHEN RSH.OldLastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, RSH.LastStatusChangeDate)
				   WHEN RSH.LastStatusChangeDate >= @ToDate THEN DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, ISNULL(@ToDate,GETDATE()))
                   ELSE DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, RSH.LastStatusChangeDate) END) AS FLOAT) HistoryInternalDowntimeInSecs
		, CAST(SUM(CASE WHEN RSH.OldAvailability = 1 OR ISNULL(ORSC.isOEELossCategory, 1) <> 1 OR ISNULL(RSH.OldResourceState,0) <> 10 THEN 0 -- Default OEE Loss Category to 1 (i.e. Schedule) if not set
                   WHEN RSH.OldLastStatusChangeDate < @FromDate THEN DATEDIFF(SECOND, @FromDate, RSH.LastStatusChangeDate)
				   WHEN RSH.LastStatusChangeDate >= @ToDate THEN DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, ISNULL(@ToDate,GETDATE()))
                   ELSE DATEDIFF(SECOND, RSH.OldLastStatusChangeDate, RSH.LastStatusChangeDate) END) AS FLOAT) HistoryExternalDowntimeInSecs
    FROM
        ResourceStatusHistory RSH
		INNER JOIN ResourceStatusCode RSC ON RSH.ResourceStatusCodeId = RSC.ResourceStatusCodeId
		INNER JOIN ResourceStatusCode ORSC ON RSH.OldResourceStatusCodeId = ORSC.ResourceStatusCodeId
    WHERE
        RSH.OldLastStatusChangeDate IS NOT NULL
		AND RSH.LastStatusChangeDate >= @FromDate
        AND RSH.OldLastStatusChangeDate <= @ToDate
    GROUP BY
        HistoryId
)
, PerformanceData AS
(
    SELECT
        ResourceId
        , CAST(SUM(ISNULL(GoodQty, 0)) AS FLOAT) TotalGoodQty
        , CAST(SUM(ISNULL(LossQty, 0)) AS FLOAT) TotalBadQty
        , CAST(SUM(ISNULL(IdealCycleTime, 0) * 60) AS FLOAT) NetOperatingTimeInSeconds -- NOTE: The IdealCycleTime is actually <Value in isIdealCycleTimes>*60*24 = NetOperatingTimeInMins
    FROM
        isOEERawDetails ORD 

    WHERE
        ORD.TxnDate >= @FromDate
        AND ORD.TxnDate <= @ToDate
    GROUP BY
        ResourceId
)
, NonscheduledTime AS
(
    SELECT
        @FromDate FromDate
        , @ToDate ToDate
        , CAST(SUM(CASE WHEN ShiftStart <= @FromDate AND ShiftEnd <= @ToDate THEN (NonscheduledTimeIsSecs * DATEDIFF(SECOND, @FromDate, ShiftEnd)) / NULLIF(ShiftDurationInSecs,0)
                   WHEN ShiftStart <= @FromDate AND ShiftEnd > @ToDate THEN (NonscheduledTimeIsSecs * DATEDIFF(SECOND, ShiftStart,  @ToDate)) / NULLIF(ShiftDurationInSecs,0)
                   WHEN ShiftStart > @FromDate AND ShiftEnd <= @ToDate THEN (NonscheduledTimeIsSecs * DATEDIFF(SECOND, ShiftStart, ShiftEnd)) / NULLIF(ShiftDurationInSecs,0)
                   WHEN ShiftStart > @FromDate AND ShiftEnd > @ToDate THEN (NonscheduledTimeIsSecs * DATEDIFF(SECOND, ShiftStart, @ToDate)) / NULLIF(ShiftDurationInSecs,0)
                   ELSE 0 END) AS FLOAT) NonscheduledTimeInSecs
    FROM
    (
        SELECT
            ShiftStart
            , ShiftEnd
            , CAST(DATEDIFF(SECOND, ShiftStart, ShiftEnd) AS FLOAT) ShiftDurationInSecs
            , CAST(isNonscheduledTime * 24 * 3600 AS FLOAT) NonscheduledTimeIsSecs
        FROM
            CalendarShift
        WHERE
            ShiftStart >= ISNULL((SELECT MAX(ShiftStart) FROM CalendarShift WHERE ShiftStart <= @FromDate AND ShiftEnd > @FromDate), @FromDate)
            AND ShiftStart < @ToDate
    ) ShiftData
)
, SummaryData AS
(
    SELECT
        R.Resource
        , R.ResourceId
		, R.Description
		, CASE WHEN R.Description LIKE '%Minime%' THEN left(R.Description, len(R.Description)-9) ELSE left(R.Description, len(R.Description)-8) END TrimmedDesc
        --, R.ResourceFamily
		--, R.ResourceType
		, R.Factory
		, R.ResourceAvailability
		, R.ResourceStatusCode
		, R.ResourceStatusReason
		--, R.OEELossCategory
        , R.CurrentDowntimeInSecs
        , R.CurrentScheduledDowntimeInSecs
        --, R.CurrentUnscheduledDowntimeInSecs
		, R.CurrentEquipmentDowntimeInSecs
		, R.CurrentInternalDowntimeInSecs
		, R.CurrentExternalDowntimeInSecs
        , ISNULL(HDT.HistoryDowntimeInSecs, 0) HistoryDowntimeInSecs
        , ISNULL(HDT.HistoryScheduledDowntimeInSecs, 0) HistoryScheduledDowntimeInSecs
        --, ISNULL(HDT.HistoryUnscheduledDowntimeInSecs, 0) HistoryUnscheduledDowntimeInSecs
		, ISNULL(HDT.HistoryEquipmentDowntimeInSecs, 0) HistoryEquipmentDowntimeInSecs
		, ISNULL(HDT.HistoryInternalDowntimeInSecs, 0) HistoryInternalDowntimeInSecs
		, ISNULL(HDT.HistoryExternalDowntimeInSecs, 0) HistoryExternalDowntimeInSecs
		--, ISNULL(HistoryCountNonscheduledTime, 0) HistoryCountNonscheduledTime
		--, ISNULL(HistoryCountUnscheduledDowntime, 0) HistoryCountUnscheduledDowntime
		--, ISNULL(HistoryCountScheduledDowntime, 0) HistoryCountScheduledDowntime
		--, ISNULL(HistoryCountEngineeringTime, 0) HistoryCountEngineeringTime
		--, ISNULL(HistoryCountProductiveTime, 0) HistoryCountProductiveTime
		--, ISNULL(HistoryCountStandbyTime, 0) HistoryCountStandbyTime
		--, ISNULL(HistoryCountEquipmentDowntime,0) HistoryCountEquipmentDowntime
        , R.DurationInSecs
		, R.sswIdealCycleTime
        , NSTD.NonscheduledTimeInSecs
		, R.DurationInSecs - (CASE WHEN @IgnoreNonScheduledTime = 1 THEN 0 ELSE NSTD.NonscheduledTimeInSecs END) AvailableProductionTimeInSecs
        , R.DurationInSecs - (CASE WHEN @IgnoreNonScheduledTime = 1 THEN 0 ELSE NSTD.NonscheduledTimeInSecs END) /* - ISNULL(HDT.HistoryScheduledDowntimeInSecs, 0)*/ PlannedProductionTimeInSecs
        , R.DurationInSecs - (CASE WHEN @IgnoreNonScheduledTime = 1 THEN 0 ELSE NSTD.NonscheduledTimeInSecs END) - ISNULL(HDT.HistoryScheduledDowntimeInSecs, 0) - ISNULL(HDT.HistoryInternalDowntimeInSecs, 0) - ISNULL(HDT.HistoryExternalDowntimeInSecs, 0) -  ISNULL(HDT.HistoryEquipmentDowntimeInSecs, 0) - R.CurrentInternalDowntimeInSecs  - R.CurrentExternalDowntimeInSecs - R.CurrentEquipmentDowntimeInSecs ActualRunningTimeInSecs
        , R.CurrentDowntimeInSecs + ISNULL(HDT.HistoryDowntimeInSecs, 0) TotalDowntimeInSecs
        , R.CurrentScheduledDowntimeInSecs + ISNULL(HDT.HistoryScheduledDowntimeInSecs, 0) TotalScheduledDowntimeInSecs
        --, R.CurrentUnscheduledDowntimeInSecs + ISNULL(HDT.HistoryUnscheduledDowntimeInSecs, 0) TotalUnscheduledDowntimeInSecs
		, R.CurrentEquipmentDowntimeInSecs + ISNULL(HDT.HistoryEquipmentDowntimeInSecs,0) TotalEquipmentDowntimeInSecs
		, R.CurrentInternalDowntimeInSecs + ISNULL(HDT.HistoryInternalDowntimeInSecs,0) TotalInternalDowntimeInSecs
		, R.CurrentExternalDowntimeInSecs + ISNULL(HDT.HistoryExternalDowntimeInSecs,0) TotalExternalDowntimeInSecs
        --, ISNULL(PD.TotalGoodQty, 0) TotalGoodQty
        --, ISNULL(PD.TotalBadQty, 0) TotalBadQty
        , ISNULL(PD.NetOperatingTimeInSeconds, 0) NetOperatingTimeInSeconds
        , R.ResourceCDOType
    FROM
        Resources R
        LEFT OUTER JOIN HistoryDowntimes HDT ON R.ResourceId = HDT.ResourceId
        LEFT OUTER JOIN PerformanceData PD ON R.ResourceId = PD.ResourceId
        INNER JOIN NonscheduledTime NSTD ON @FromDate = NSTD.FromDate
)

    SELECT
		CASE WHEN SD.TrimmedDesc LIKE '%Laser%' then 1
			   WHEN SD.TrimmedDesc LIKE '%PCBA%' then 2
			   WHEN SD.TrimmedDesc LIKE '%HI-POT%' then 3
			   WHEN SD.TrimmedDesc LIKE '%Test 1%' then 4
			   WHEN SD.TrimmedDesc LIKE '%Test 2%' then 5
			   WHEN SD.TrimmedDesc LIKE '%Test 3%' then 6
			   WHEN SD.TrimmedDesc LIKE '%Visual%' then 7
			   WHEN SD.TrimmedDesc LIKE '%Weighing%' then 8
			   WHEN SD.TrimmedDesc LIKE '%Backend%' then 9 END No
        , Resource
		, Description
        --, ResourceFamily
        --, ResourceType
		--, Factory
		, CASE WHEN ResourceAvailability = 1 THEN 'Up'
				WHEN ResourceAvailability = 2 THEN 'Down'
				ELSE '-' END ResourceAvailability
		--, CASE WHEN ResourceAvailability IS NULL THEN 'Orange'
				--WHEN ResourceAvailability = 1 THEN 'DarkGreen' 
				--ElSE 'Red' END ResourceAvailabilityColor
		, ResourceStatusCode
		, ResourceStatusReason
		--, OEELossCategory
		--, NetOperatingTimeInSeconds
        --, CASE WHEN TotalGoodQty + TotalBadQty > 0 THEN NetOperatingTimeInSeconds / NULLIF((TotalGoodQty + TotalBadQty),0) ELSE 0 END IdealCycleTimeInSeconds
        , DurationInSecs
        , NonscheduledTimeInSecs
        --, CurrentDowntimeInSecs
		--, CurrentScheduledDowntimeInSecs
		--, CurrentUnscheduledDowntimeInSecs
		--, CurrentEquipmentDowntimeInSecs
        --, HistoryDowntimeInSecs
		--, HistoryScheduledDowntimeInSecs
		--, HistoryUnscheduledDowntimeInSecs
		--, HistoryEquipmentDowntimeInSecs
		--, HistoryCountNonscheduledTime
		--, HistoryCountUnscheduledDowntime
		--, HistoryCountScheduledDowntime
		--, HistoryCountEngineeringTime
		--, HistoryCountProductiveTime
		--, HistoryCountStandbyTime
		--, HistoryCountEquipmentDowntime
        , PlannedProductionTimeInSecs
        , CASE WHEN ActualRunningTimeInSecs > 0 THEN ActualRunningTimeInSecs ELSE 0 END ActualRunningTimeInSecs
        , TotalDowntimeInSecs
        , TotalScheduledDowntimeInSecs
		--, TotalUnscheduledDowntimeInSecs
		, TotalEquipmentDowntimeInSecs
		, TotalInternalDowntimeInSecs
		, TotalExternalDowntimeInSecs
        --, TotalGoodQty
        --, TotalBadQty
		, ISNULL (FPY.fpy2, CounterResourceMove) TotalGoodQty
		, ISNULL (FPY.ng, 0) TotalBadQty
		, CASE WHEN PlannedProductionTimeInSecs > 0 AND ActualRunningTimeInSecs > 0 THEN ActualRunningTimeInSecs / NULLIF(PlannedProductionTimeInSecs,0) ELSE 0 END AvailabilityValue
		, CASE WHEN PlannedProductionTimeInSecs > 0 AND ActualRunningTimeInSecs > 0 THEN (PlannedProductionTimeInSecs-TotalEquipmentDowntimeInSecs)/NULLIF(PlannedProductionTimeInSecs,0) ELSE 0 END AvailabilityTPMEValue
		, CASE WHEN DurationInSecs > 0 AND PlannedProductionTimeInSecs > 0 THEN PlannedProductionTimeInSecs / NULLIF(DurationInSecs,0) ELSE 0 END UtilisationValue
        --, CASE WHEN ActualRunningTimeInSecs > 0 THEN ISNULL((TotalGoodQty+TotalBadQty)/NULLIF((ActualRunningTimeInSecs/(sswIdealCycleTime*24*3600)),0),0) ELSE 0 END PerformanceValue
        , CASE WHEN ActualRunningTimeInSecs > 0 THEN ISNULL((fpy2+ng)/NULLIF((ActualRunningTimeInSecs/(sswIdealCycleTime*24*3600)),0), CounterResourceMove / NULLIF((ActualRunningTimeInSecs/(sswIdealCycleTime*24*3600)),0)) ELSE 0 END PerformanceValue
		--, CASE WHEN TotalGoodQty + TotalBadQty > 0 THEN TotalGoodQty / NULLIF((TotalGoodQty + TotalBadQty),0) ELSE 0 END QualityValue
		, CASE WHEN ISNULL(CAST(fpy2 + ng as FLOAT), 1) > 0 THEN ISNULL((CAST(fpy2 as FLOAT) / CAST(fpy2 + ng as FLOAT)),1) ELSE 0 END QualityValue
    FROM
        SummaryData SD
		FULL OUTER JOIN OLTPSCHEMA.tskFPYTotal (@FromDate, @ToDate, @ResourceGroup, @Resource, '%') FPY on FPY.ResourceName = SD.Resource
		FULL OUTER JOIN OLTPSCHEMA.wikResourceGroupCounter(@ResourceGroup, '%', @FromDate, @ToDate) RC on RC.ResourceName = SD.Resource

	WHERE
		SD.Resource IS NOT NULL

	ORDER BY
		No ASC OFFSET 0 ROWS

GO
SELECT * FROM OLTPSCHEMA.sswFuncOEERawData ('%', 'BW01-NM4', '%', '12/15/2022 08:00:00', '12/15/2022 17:00:00', 0)
