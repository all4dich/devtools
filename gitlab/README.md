# GitLab API Usage Example

## Introduction
This document provides an example of how to use the GitLab API to manage GitLab projects, users, and groups.

## References
* [GitLab API Documentation](https://docs.gitlab.com/ee/api/)

## Namespace
* [GitLab API Documentation for Namespaces](https://docs.gitlab.com/ee/api/namespaces.html)

### Get Namespace ID with namespace name
* API
  * GET /namespaces
* Steps
  * Get a list of namespaces
  * Find the namespace with the name that you are looking for
  * Get the ID of the namespace
  * Break out of the loop
* Example
  * [call-gitlab-api.py](call-gitlab-api.py)
    * get_namespace_id()
    
## Project
* [GitLab APi Documentation for Projects](https://docs.gitlab.com/ee/api/projects.html)
### Create a project
* API
  * POST /projects
* Required Parameters
  * name
    * The name of the project
    * Displayed in the GitLab UI
  * path
    * The path of the project
    * Used in the URL
  * namespace_id
    * The ID of the namespace
    * The namespace is the group that the project belongs to
    * Integer Type
    * The ID can be found by querying the GitLab API
  * visibility
    * ```private```, ```internal```, or ```public```
  * initialize_with_readme
  * visibility
    * ```true``` or ```false```
* Steps
  * Get the ID of the namespace
  * Use the ID to create the project
* Example
  * ```python
      url = f"{GITLAB_URL}/api/v4/projects"
      headers = {"Authorization": f"Bearer {GITLAB_TOKEN}"}  
      namespace_id = get_namespace_id(org_name)  
      data = {  
          "name": repo_name,  
          "description": "This is a project",  
          "path": repo_name,  
          "namespace_id": namespace_id,  
          "initialize_with_readme": "false",  
          "visibility": "private"  
      }  
      response = requests.post(url, headers=headers, data=data, verify=SSL_CERT_VERIFY)        
        ```
### Delete a project
* API
  * DELETE /projects/:id
* Required Parameters
  * id
    * The ID of the project
    * Integer Type
    * The ID can be found by querying the GitLab API
* Steps
  * Get the ID of the project
  * Use the ID to delete the project
* Example
  * ```python
      url = f"{GITLAB_URL}/api/v4/projects/{project_id}"
      headers = {"Authorization": f"Bearer <GITLAB_TOKEN>"}
      response = requests.delete(url, headers=headers, verify=SSL_CERT_VERIFY)
        ```
### Get a list of projects
* API
  * GET /projects
* Required Parameters
  * None
* Steps
  * Get a list of projects by paging through the results
* Example
  * Use call-gitlab-api.py > get_projects_list()
