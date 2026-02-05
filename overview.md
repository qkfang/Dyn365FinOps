This extension provides Azure DevOps build and release tasks for [Dynamics 365 Finance and Operations](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/dev-tools/developer-home-page#build-automation-using-azure) and [Dynamics Lifecycle Services](https://lcs.dynamics.com). 

## How to Use

After installing the extension, you can add tasks to new or existing build and release pipelines. Some tasks are only available in release or build pipelines, depending on their purpose.

## Available Tasks

* **Dynamics Lifecycle Services (LCS) Asset Upload** : Upload a software deployable package to an LCS project's Asset Library. This task is only available as a release pipeline task. It requires an LCS connection to be setup in the Azure DevOps project's service connections. For more information, see [Upload assets by using Azure Pipelines](https://go.microsoft.com/fwlink/?linkid=2141947).
<br/> **_NOTE: Review the known limitations and issues below._** 

* **Dynamics Lifecycle Services (LCS) Asset Download** : Download assets from an LCS project's Asset Library. This task requires an LCS connection to be setup in the Azure DevOps project's service connections. For more information, see [Download assets by using Azure Pipelines](https://go.microsoft.com/fwlink/?linkid=2141867).
<br/> **_NOTE: Review the known limitations and issues below._** 

* **Dynamics Lifecycle Services (LCS) Asset Deployment** :
 This task is only available as a release pipeline task. It requires an LCS connection to be setup in the Azure DevOps project's service connections. For more information, see [Deploy assets by using Azure Pipelines](https://go.microsoft.com/fwlink/?linkid=2141868).
  <br/> **_NOTE: Review the known limitations and issues below._**
  <br/> Here are the type of assets that you can deploy using this task:
   * Software deployable package from an LCS project's Asset Library to a **non-production** environment. By design it does not allow deploying to production environments, and in line with the LCS portal it does not allow deploying software deployable packages to build environments. **Update the version of the task used in your pipeline to 1.\* or higher to take advantage of self-service environment support**.
   * Commerce scale unit extension from an LCS project's Asset Library to a Commerce Scale Unit. **Update the version of the task used in your pipeline to 3.\* or higher to enable this asset type deployment**.
   * e-Commerce package from an LCS project's Asset Library to a e-Commerce environment. **Update the version of the task used in your pipeline to 3.\* or higher to enable this asset type deployment**.

* **Create Deployable Package** : Create a deployable package from a set of compiled X++ binaries. This task is available in both build and release pipelines. It requires the X++ compiler tools. For more information, see [Create deployable packages in Azure Pipelines](https://go.microsoft.com/fwlink/?linkid=2128586).

* **Add Licenses to Deployable Package** : Add license files to a deployable package. This task is available in both build and release pipelines. For more information, see [Add license files to a deployable package in Azure Pipelines](https://go.microsoft.com/fwlink/?linkid=2128832).

* **Update Model Version** : Update model descriptors' versions during build. This task is available in both build and release pipelines. The task needs to execute before running the build of the model in question, and it only updates the local copy of the descriptor during build and does not affect the descriptor present in source control. For more information, see [X++ model-versioning in Azure Pipelines](https://go.microsoft.com/fwlink/?linkid=2128587).

## Known Limitations and Issues
* LCS Authentication requires AAD accounts that do not have MFA enabled, and are not backed by federated logins. We are reviewing options for new authentication features in LCS that can enable the API and these tasks to authenticate under such setups, such as service-to-service authentication.

## Feedback and Issues

For issues, please use [regular support options for Dynamics 365 Finance and Operations](https://lcs.dynamics.com).
