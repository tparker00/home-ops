import os

AUTHENTICATION_SOURCES = ['oauth2', 'internal']
OAUTH2_AUTO_CREATE_USER = True
MASTER_PASSWORD_REQUIRED = False
OAUTH2_CONFIG = [{
    'OAUTH2_NAME' : 'pocketid',
    'OAUTH2_DISPLAY_NAME' : 'pgAdmin SSO',
    'OAUTH2_CLIENT_ID' : os.environ.get('OIDC_CLIENT_ID'),
    'OAUTH2_CLIENT_SECRET' : os.environ.get('OIDC_CLIENT_SECRET'),
    'OAUTH2_TOKEN_URL' : 'https://id.${SECRET_DOMAIN}/api/oidc/token',
    'OAUTH2_AUTHORIZATION_URL' : 'https://id.${SECRET_DOMAIN}/authorize',
    'OAUTH2_API_BASE_URL' : 'https://id.${SECRET_DOMAIN}',
    'OAUTH2_USERINFO_ENDPOINT' : 'https://id.${SECRET_DOMAIN}/api/oidc/userinfo',
    'OAUTH2_SERVER_METADATA_URL' : 'https://id.${SECRET_DOMAIN}/.well-known/openid-configuration',
    'OAUTH2_LOGOUT_URL' : 'https://id.${SECRET_DOMAIN}/api/oidc/end-session',
    'OAUTH2_SCOPE' : 'openid email profile',
    'OAUTH2_ICON' : 'fa-openid',
    'OAUTH2_BUTTON_COLOR' : '#2db1fd'
}]
