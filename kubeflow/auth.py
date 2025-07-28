import requests
from bs4 import BeautifulSoup

def extract_hrefs_from_string(html_string):
    """Extract href values from HTML string"""
    soup = BeautifulSoup(html_string, 'html.parser')
    links = soup.find_all('a', href=True)
    return [link['href'] for link in links]

def kubeflow_authenticate_and_get_cookie(host: str, username: str, password: str, auth_suffix: str = "/oauth2/start", auth_type="ldap"):
    session = requests.Session()
    auth_url = f"{host}{auth_suffix}"
    session_response = session.get(auth_url)
    # Since 1.9.1 cookie's name is `oauth2_proxy_kubeflow_csrf`
    # cookie_name = "oidc_state_csrf" # For Kubeflow Manifest 1.8.1
    # cookie_name = "oauth2_proxy_kubeflow_csrf"
    cookie_name = session.cookies.keys()[0]
    cookie_value_1 = session.cookies.get(cookie_name)
    href_values = extract_hrefs_from_string(session_response.text)
    auth_request_url = ""
    for href_url in href_values:
        if href_url.split("/")[3].split("?")[0] == auth_type:
            auth_request_url = host + href_url
            break
    auth_response = session.get(auth_request_url, cookies={cookie_name: cookie_value_1}, verify=False)
    login_request_url = auth_response.url
    login_response = session.post(login_request_url, data={"login": username, "password": password}, verify=False,
                                  cookies={cookie_name: cookie_value_1})
    login_response.raise_for_status()
    print(session.cookies)
    cookie_return = None
    for a_cookie in session.cookies:
        # login_cookie_name = "oauth2_proxy_kubeflow" # For Kubeflow 1.9.1 and later
        # login_cookie_name = "authservice_session" # For Kubeflow 1.8.1
        login_cookie_name = a_cookie.name
        login_cookie_value = a_cookie.value
        cookie_return = f"{login_cookie_name}={login_cookie_value}"
        break
    return cookie_return