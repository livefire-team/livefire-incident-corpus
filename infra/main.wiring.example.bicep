// Example only: how a team's main.bicep calls the two WS3 modules. Copy the two module blocks into your main.bicep
// and map each input to your own outputs. The comments say which workstream provides each one.
targetScope = 'subscription'

param location string
param principalId string                       // whoever runs the deployment: may load the search index
param mcpImage string                          // <registry>/mcp-server:sha-<commit> (CI or the deploy script pushes it)
param githubRepo string                        // owner/name
param githubPlannerAppId string
param githubPlannerInstallationId string       // a number, from the installation's URL (not the App's Client ID)
param githubEngineerAppId string
param githubEngineerInstallationId string
param mcpAuthMode string = 'key'               // key (per-endpoint keys) or entra (agent identities)
param mcpClientId string = ''                  // entra: from scripts/setup-entra.sh
param plannerAgentObjectId string = ''         // entra: from WS4
param engineerAgentObjectId string = ''
param recoveryAgentObjectId string = ''

// --- provided by the platform (WS2) and the twin (WS1); replace with your own modules' outputs
param controlRgName string
param twinRgName string
param registryServer string                    // the private registry login server
param pullIdentityId string                    // resource ID of the identity that pulls images (AcrPull only)
param environmentId string                     // the Container Apps environment the MCP server joins
param keyVaultName string                      // the control vault holding the secrets from scripts/create-secrets.sh
param evidenceAccountName string               // the evidence storage account
param evidenceBlobUrl string                   // https://<account>.blob.core.windows.net/evidence
param opsUrl string                            // WS2's Ops Service internal URL (the Recovery tools call it)
param twinKeyVaultId string
param twinKeyVaultName string
param appIdentityPrincipalId string            // the order service's managed identity (principal ID)
param logAnalyticsCustomerId string            // the twin's Log Analytics workspace ID (customer ID)
param logAnalyticsWorkspaceName string
param orderAppName string
param twinSqlServerName string
param desiredSqlDbName string = 'orders'
@allowed(['rbac', 'accessPolicy'])
param kvPermissionModel string = 'rbac'          // the twin vault's model (WS1/WS2: same value as the twin module)

resource controlRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = { name: controlRgName }
resource twinRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = { name: twinRgName }

module mcp 'modules/mcp.bicep' = { // WS3: the MCP server (ca-mcp), its identity, and AI Search
  scope: controlRg
  name: 'mcp'
  params: {
    location: location
    environmentId: environmentId
    image: mcpImage
    principalId: principalId
    registryServer: registryServer
    pullIdentityId: pullIdentityId
    keyVaultName: keyVaultName
    evidenceAccountName: evidenceAccountName
    evidenceBlobUrl: evidenceBlobUrl
    twinKeyVaultId: twinKeyVaultId
    appIdentityPrincipalId: appIdentityPrincipalId
    logAnalyticsCustomerId: logAnalyticsCustomerId
    orderAppName: orderAppName
    twinSqlServerName: twinSqlServerName
    desiredSqlDbName: desiredSqlDbName
    githubRepo: githubRepo
    githubPlannerAppId: githubPlannerAppId
    githubPlannerInstallationId: githubPlannerInstallationId
    githubEngineerAppId: githubEngineerAppId
    githubEngineerInstallationId: githubEngineerInstallationId
    authMode: mcpAuthMode
    mcpClientId: mcpClientId
    plannerAgentObjectId: plannerAgentObjectId
    engineerAgentObjectId: engineerAgentObjectId
    recoveryAgentObjectId: recoveryAgentObjectId
    opsUrl: opsUrl
  }
}

module mcpTwinAccess 'modules/mcp-twin-access.bicep' = { // WS3: the evidence tools' read roles on the twin
  scope: twinRg
  name: 'mcp-twin-access'
  params: {
    mcpPrincipalId: mcp.outputs.mcpIdentityPrincipalId
    twinKeyVaultName: twinKeyVaultName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    sqlServerName: twinSqlServerName
    orderAppName: orderAppName
    kvPermissionModel: kvPermissionModel
  }
}

output MCP_URL string = mcp.outputs.mcpUrl                 // WS4: the agents' MCP connections
output SEARCH_ENDPOINT string = mcp.outputs.searchEndpoint // scripts/load-incidents.py, WS4's knowledge loop
output SEARCH_NAME string = mcp.outputs.searchName
