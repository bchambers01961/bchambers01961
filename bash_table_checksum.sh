#!/bin/bash

# Define the list of tables
tables=(
"AccountAllocation" "AggregatedCounter" "AleGroup" "AleType" "Asset" "AssetAuditLog" "AssetInfo" "AssetLedgerEntry" "AssetNote" "AssetProduct" "AssetSummary" "AuditEntry" "AuditEntryProperty" 
"Config" "ContractType" "Counter" "DistributedLock" "Hash" "InterfaceAle" "InterfaceAsset" "InterfaceAssetInfo" "InterfaceAssetLog" "InterfaceProduct" "Invoice" "InvoiceLine" "Job" 
"JobParameter" "JobProgress" "JobQueue" "JobState" "List" "Note" "Notification" "OOCPaymentTerm" "Partner" "PartnerInfo" "PartnerInfoType" "PartnerNote" "PartnerRateAdjustment" 
"PartnerServiceProvider" "PartnerServiceProviderOOCPaymentTerm" "PaymentData" "PaymentDataBatch" "PaymentDataBatchSummary" "PaymentDataRaw" "Product" "ProductClass" "ProductGroup" "ProductRate" 
"ProductRateType" "ProductRateValue" "ProductType" "ProductTypeAssetInfo" "ProductVariant" "Proof" "ProofInfo" "Server" "ServiceProvider" "ServiceProviderAccountType" 
"ServiceProviderPaymentType" "ServiceProviderRate" "ServiceProviderUpliftRate" "Set" "SpendCap" "SpendCapPeriod" "State" "__EFMigrationsHistory" "temp_ALE_Jeff" "temp_ALE_SN" 
"temp_ActivationIds" "temp_Asset" "temp_AssetChangeIds" "temp_AssetInfo" "temp_AssetLedgerEntry" "temp_AssetMissing" "temp_AssetProduct" "temp_Asset_SourceRef" "temp_InterfaceAsset" 
"temp_MarFix" "temp_MissingAssetInfo" "temp_MissingProductRates" "temp_MissingProductRates2" "temp_Partner" "temp_PartnerInfo" "temp_Product" "temp_ProductRate" "temp_ProductRate2" 
"temp_ProductRateValue" "temp_ProductRateValue2" "temp_Proof" "temp_SB" "temp_SBCN" "temp_SBI" "temp_SBI_SBCN" "temp_SB_Missing" "temp_SecondaryProduct" "temp_SecondaryProduct2" 
"temp_ThirdPartyInvoiceIds" "temp_assetchangeupdate" "temp_ce" "temp_prodidupdate" "temp_proofupdate" "temp_updateDate" "temp_updateOA" "temp_updateSP" "temp_updatesubscriber"
)

# Define the connection details for both servers
server1_host="affinitycommissions.cluster-ro-chtyi7kcjwww.eu-west-2.rds.amazonaws.com"
server1_user="admin"
server1_password="6vKSGteW5eGJbJvpwr9A"
server1_database="affinitycommissions"

server2_host="affinitycommissions8.cluster-chtyi7kcjwww.eu-west-2.rds.amazonaws.com"
server2_user="admin"
server2_password="6vKSGteW5eGJbJvpwr9A"
server2_database="affinitycommissions"

# Function to run checksums on a server
run_checksums() {
    local host=$1
    local user=$2
    local password=$3
    local database=$4
    local output_file=$5

    # Clear the output file
    > "$output_file"

    for table in "${tables[@]}"; do
        checksum=$(mysql -h "$host" -u "$user" -p"$password" -D "$database" -e "CHECKSUM TABLE \`$table\`;" | tail -n 1)
        echo "Checksum for $table on $host: $checksum" >> "$output_file"
    done
}
run_rowcounts() {
    local host=$1
    local user=$2
    local password=$3
    local database=$4
    local output_file=$5

    # Clear the output file
    > "$output_file"

    for table in "${tables[@]}"; do
        checksum=$(mysql -h "$host" -u "$user" -p"$password" -D "$database" -e "SELECT COUNT(*) FROM \`$table\`;" | tail -n 1)
        echo "Row Count for $table on $host: $checksum" >> "$output_file"
    done
}

# Run checksums on both servers in parallel
run_checksums "$server1_host" "$server1_user" "$server1_password" "$server1_database" "server1_checksums.txt" &
run_checksums "$server2_host" "$server2_user" "$server2_password" "$server2_database" "server2_checksums.txt" &

# Wait for both background processes to finish
wait

# Run rowcounts on both servers in parrallel
run_rowcounts "$server1_host" "$server1_user" "$server1_password" "$server1_database" "server1_rowcounts.txt" &
run_rowcounts "$server2_host" "$server2_user" "$server2_password" "$server2_database" "server2_rowcounts.txt" &

# Wait for both background processes to finish
wait

# Combine and sort the results
cat server1_checksums.txt server2_checksums.txt server1_rowcounts.txt server2_rowcounts.txt | sort > server_comparison.txt

# Display the sorted results
less server_comparison.txt

# Remove original outputs
rm server1_checksums.txt server2_checksums.txt server1_rowcounts.txt server2_rowcounts.txt