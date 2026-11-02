// Read-only roles for id-lf-mcp on the twin (WS3). Deploy with scope: the twin resource group.
param mcpPrincipalId string
param twinKeyVaultName string
param logAnalyticsWorkspaceName string
@description('v2.0: the twin SQL server and order app, for get_network_rules and get_app_configuration. Empty skips.')
param sqlServerName string = ''
param orderAppName string = ''

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893'
// Key Vault Reader: vault and secret metadata (secrets/readMetadata), never secret values
var keyVaultReaderRoleId = '21090545-7ca7-4776-b22c-e363652d74d2'

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: twinKeyVaultName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// Management-plane read only: role assignments and vault properties, never secrets
resource vaultReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, mcpPrincipalId, readerRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: mcpPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource logsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, mcpPrincipalId, logAnalyticsReaderRoleId)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
    principalId: mcpPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// v2.0: get_secret_metadata lists the db-password secret's versions; Key Vault Reader can't read any value
resource vaultMetadataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, mcpPrincipalId, keyVaultReaderRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultReaderRoleId)
    principalId: mcpPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' existing = if (!empty(sqlServerName)) {
  name: sqlServerName
}

// v2.0: get_network_rules reads the server's public access and firewall rules
resource sqlReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sqlServerName)) {
  name: guid(sqlServer.id, mcpPrincipalId, readerRoleId)
  scope: sqlServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: mcpPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource orderApp 'Microsoft.App/containerApps@2024-03-01' existing = if (!empty(orderAppName)) {
  name: orderAppName
}

// v2.0: get_app_configuration reads the order app's revisions and settings (secret values stay in secretRefs)
resource appReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(orderAppName)) {
  name: guid(orderApp.id, mcpPrincipalId, readerRoleId)
  scope: orderApp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: mcpPrincipalId
    principalType: 'ServicePrincipal'
  }
}
