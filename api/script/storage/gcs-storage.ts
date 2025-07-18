// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

import * as q from "q";
import * as shortid from "shortid";
import * as stream from "stream";
import * as storage from "./storage";
import * as utils from "../utils/common";

import { Storage } from "@google-cloud/storage";
import { Datastore, Key } from "@google-cloud/datastore";

import Promise = q.Promise;

interface GCSConfig {
  projectId: string;
  bucketName: string;
  keyFilename?: string;
  credentials?: any;
}

export class GCSStorage implements storage.Storage {
  private _storage: Storage;
  private _datastore: Datastore;
  private _bucket: any;
  private _config: GCSConfig;

  constructor(config?: GCSConfig) {
    this._config = config || {
      projectId: process.env.GOOGLE_CLOUD_PROJECT || process.env.GCP_PROJECT_ID,
      bucketName: process.env.GCS_BUCKET_NAME || process.env.GCP_BUCKET_NAME,
      keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
      credentials: process.env.GCP_CREDENTIALS ? JSON.parse(process.env.GCP_CREDENTIALS) : undefined
    };

    const clientConfig: any = {
      projectId: this._config.projectId
    };

    if (this._config.keyFilename) {
      clientConfig.keyFilename = this._config.keyFilename;
    }
    if (this._config.credentials) {
      clientConfig.credentials = this._config.credentials;
    }

    this._storage = new Storage(clientConfig);
    this._datastore = new Datastore(clientConfig);
    this._bucket = this._storage.bucket(this._config.bucketName);
  }

  public checkHealth(): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      // Check Datastore connection
      this._datastore.runQuery(
        this._datastore.createQuery("__kind__").limit(1)
      ).then(() => {
        // Check Storage bucket access
        return this._bucket.exists();
      }).then(([exists]: [boolean]) => {
        if (exists) {
          resolve();
        } else {
          reject(storage.storageError(storage.ErrorCode.ConnectionFailed, `GCS bucket ${this._config.bucketName} does not exist`));
        }
      }).catch((error: any) => {
        reject(storage.storageError(storage.ErrorCode.ConnectionFailed, `GCS health check failed: ${error.message}`));
      });
    });
  }

  // Account Management
  public addAccount(account: storage.Account): Promise<string> {
    return q.Promise<string>((resolve, reject) => {
      const id = shortid.generate();
      const key = this._datastore.key(["Account", id]);
      
      const entity = {
        key: key,
        data: {
          ...account,
          id: id,
          createdTime: Date.now()
        }
      };

      this._datastore.save(entity).then(() => {
        resolve(id);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getAccount(accountId: string): Promise<storage.Account> {
    return q.Promise<storage.Account>((resolve, reject) => {
      const key = this._datastore.key(["Account", accountId]);
      
      this._datastore.get(key).then(([entity]) => {
        if (!entity) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `Account ${accountId} not found`));
          return;
        }
        resolve(entity);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getAccountByEmail(email: string): Promise<storage.Account> {
    return q.Promise<storage.Account>((resolve, reject) => {
      const query = this._datastore.createQuery("Account")
        .filter("email", "=", email)
        .limit(1);

      this._datastore.runQuery(query).then(([entities]) => {
        if (entities.length === 0) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `Account with email ${email} not found`));
          return;
        }
        resolve(entities[0]);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getAccountIdFromAccessKey(accessKey: string): Promise<string> {
    return q.Promise<string>((resolve, reject) => {
      const query = this._datastore.createQuery("AccessKey")
        .filter("name", "=", accessKey)
        .limit(1);

      this._datastore.runQuery(query).then(([entities]) => {
        if (entities.length === 0) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `Access key ${accessKey} not found`));
          return;
        }
        
        const accessKeyEntity = entities[0];
        if (accessKeyEntity.expires && accessKeyEntity.expires < Date.now()) {
          reject(storage.storageError(storage.ErrorCode.Expired, "Access key has expired"));
          return;
        }
        
        resolve(accessKeyEntity.accountId);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public updateAccount(email: string, updates: storage.Account): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      this.getAccountByEmail(email).then((account: storage.Account) => {
        const key = this._datastore.key(["Account", account.id]);
        const mergedAccount = { ...account, ...updates };
        
        const entity = {
          key: key,
          data: mergedAccount
        };

        return this._datastore.save(entity);
      }).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  // App Management
  public addApp(accountId: string, app: storage.App): Promise<storage.App> {
    return q.Promise<storage.App>((resolve, reject) => {
      const id = shortid.generate();
      const key = this._datastore.key(["App", id]);
      
      const newApp: storage.App = {
        ...app,
        id: id,
        createdTime: Date.now(),
        collaborators: {
          [accountId]: {
            accountId: accountId,
            permission: storage.Permissions.Owner,
            isCurrentAccount: true
          }
        }
      };

      const entity = {
        key: key,
        data: {
          ...newApp,
          accountId: accountId // For querying apps by account
        }
      };

      this._datastore.save(entity).then(() => {
        resolve(newApp);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getApps(accountId: string): Promise<storage.App[]> {
    return q.Promise<storage.App[]>((resolve, reject) => {
      const query = this._datastore.createQuery("App")
        .filter("accountId", "=", accountId);

      this._datastore.runQuery(query).then(([entities]) => {
        const apps = entities.map(entity => ({
          ...entity,
          collaborators: entity.collaborators || {}
        }));
        resolve(apps);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getApp(accountId: string, appId: string): Promise<storage.App> {
    return q.Promise<storage.App>((resolve, reject) => {
      const key = this._datastore.key(["App", appId]);
      
      this._datastore.get(key).then(([entity]) => {
        if (!entity) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `App ${appId} not found`));
          return;
        }
        
        // Check if account has access to this app
        if (entity.accountId !== accountId && 
            (!entity.collaborators || !entity.collaborators[accountId])) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `App ${appId} not found`));
          return;
        }
        
        resolve(entity);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public removeApp(accountId: string, appId: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      this.getApp(accountId, appId).then(() => {
        const key = this._datastore.key(["App", appId]);
        return this._datastore.delete(key);
      }).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public transferApp(accountId: string, appId: string, email: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      // Implementation for app transfer
      reject(storage.storageError(storage.ErrorCode.Other, "App transfer not implemented"));
    });
  }

  public updateApp(accountId: string, app: storage.App): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      this.getApp(accountId, app.id).then((existingApp) => {
        const key = this._datastore.key(["App", app.id]);
        const mergedApp = { ...existingApp, ...app };
        
        const entity = {
          key: key,
          data: mergedApp
        };

        return this._datastore.save(entity);
      }).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  // Collaborator Management
  public addCollaborator(accountId: string, appId: string, email: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      reject(storage.storageError(storage.ErrorCode.Other, "Collaborator management not implemented"));
    });
  }

  public getCollaborators(accountId: string, appId: string): Promise<storage.CollaboratorMap> {
    return q.Promise<storage.CollaboratorMap>((resolve, reject) => {
      this.getApp(accountId, appId).then((app) => {
        resolve(app.collaborators || {});
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public removeCollaborator(accountId: string, appId: string, email: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      reject(storage.storageError(storage.ErrorCode.Other, "Collaborator management not implemented"));
    });
  }

  // Deployment Management
  public addDeployment(accountId: string, appId: string, deployment: storage.Deployment): Promise<string> {
    return q.Promise<string>((resolve, reject) => {
      const id = shortid.generate();
      const key = this._datastore.key(["Deployment", id]);
      
      const newDeployment: storage.Deployment = {
        ...deployment,
        id: id,
        createdTime: Date.now(),
        key: shortid.generate() // Generate deployment key
      };

      const entity = {
        key: key,
        data: {
          ...newDeployment,
          accountId: accountId,
          appId: appId
        }
      };

      this._datastore.save(entity).then(() => {
        resolve(id);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getDeployment(accountId: string, appId: string, deploymentId: string): Promise<storage.Deployment> {
    return q.Promise<storage.Deployment>((resolve, reject) => {
      const key = this._datastore.key(["Deployment", deploymentId]);
      
      this._datastore.get(key).then(([entity]) => {
        if (!entity || entity.accountId !== accountId || entity.appId !== appId) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `Deployment ${deploymentId} not found`));
          return;
        }
        resolve(entity);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getDeploymentInfo(deploymentKey: string): Promise<storage.DeploymentInfo> {
    return q.Promise<storage.DeploymentInfo>((resolve, reject) => {
      const query = this._datastore.createQuery("Deployment")
        .filter("key", "=", deploymentKey)
        .limit(1);

      this._datastore.runQuery(query).then(([entities]) => {
        if (entities.length === 0) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `Deployment with key ${deploymentKey} not found`));
          return;
        }
        
        const deployment = entities[0];
        resolve({
          appId: deployment.appId,
          deploymentId: deployment.id
        });
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getDeployments(accountId: string, appId: string): Promise<storage.Deployment[]> {
    return q.Promise<storage.Deployment[]>((resolve, reject) => {
      const query = this._datastore.createQuery("Deployment")
        .filter("accountId", "=", accountId)
        .filter("appId", "=", appId);

      this._datastore.runQuery(query).then(([entities]) => {
        resolve(entities);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public removeDeployment(accountId: string, appId: string, deploymentId: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      this.getDeployment(accountId, appId, deploymentId).then(() => {
        const key = this._datastore.key(["Deployment", deploymentId]);
        return this._datastore.delete(key);
      }).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public updateDeployment(accountId: string, appId: string, deployment: storage.Deployment): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      this.getDeployment(accountId, appId, deployment.id).then((existingDeployment) => {
        const key = this._datastore.key(["Deployment", deployment.id]);
        const mergedDeployment = { ...existingDeployment, ...deployment };
        
        const entity = {
          key: key,
          data: mergedDeployment
        };

        return this._datastore.save(entity);
      }).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  // Package Management
  public commitPackage(accountId: string, appId: string, deploymentId: string, appPackage: storage.Package): Promise<storage.Package> {
    return q.Promise<storage.Package>((resolve, reject) => {
      reject(storage.storageError(storage.ErrorCode.Other, "Package management not fully implemented"));
    });
  }

  public clearPackageHistory(accountId: string, appId: string, deploymentId: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      reject(storage.storageError(storage.ErrorCode.Other, "Package history management not implemented"));
    });
  }

  public getPackageHistoryFromDeploymentKey(deploymentKey: string): Promise<storage.Package[]> {
    return q.Promise<storage.Package[]>((resolve, reject) => {
      reject(storage.storageError(storage.ErrorCode.Other, "Package history retrieval not implemented"));
    });
  }

  public getPackageHistory(accountId: string, appId: string, deploymentId: string): Promise<storage.Package[]> {
    return q.Promise<storage.Package[]>((resolve, reject) => {
      reject(storage.storageError(storage.ErrorCode.Other, "Package history retrieval not implemented"));
    });
  }

  public updatePackageHistory(accountId: string, appId: string, deploymentId: string, history: storage.Package[]): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      reject(storage.storageError(storage.ErrorCode.Other, "Package history update not implemented"));
    });
  }

  // Blob Management
  public addBlob(blobId: string, addstream: stream.Readable, streamLength: number): Promise<string> {
    return q.Promise<string>((resolve, reject) => {
      const file = this._bucket.file(`blobs/${blobId}`);
      const stream = file.createWriteStream({
        metadata: {
          contentLength: streamLength
        }
      });

      stream.on('error', (error: any) => {
        reject(this._convertError(error));
      });

      stream.on('finish', () => {
        resolve(blobId);
      });

      addstream.pipe(stream);
    });
  }

  public getBlobUrl(blobId: string): Promise<string> {
    return q.Promise<string>((resolve, reject) => {
      const file = this._bucket.file(`blobs/${blobId}`);
      
      // Generate signed URL valid for 1 hour
      file.getSignedUrl({
        action: 'read',
        expires: Date.now() + 60 * 60 * 1000 // 1 hour
      }).then((urls) => {
        resolve(urls[0]);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public removeBlob(blobId: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      const file = this._bucket.file(`blobs/${blobId}`);
      
      file.delete().then(() => {
        resolve();
      }).catch((error: any) => {
        if (error.code === 404) {
          resolve(); // Already deleted
        } else {
          reject(this._convertError(error));
        }
      });
    });
  }

  // Access Key Management
  public addAccessKey(accountId: string, accessKey: storage.AccessKey): Promise<string> {
    return q.Promise<string>((resolve, reject) => {
      const id = shortid.generate();
      const key = this._datastore.key(["AccessKey", id]);
      
      const newAccessKey: storage.AccessKey = {
        ...accessKey,
        id: id,
        createdTime: Date.now()
      };

      const entity = {
        key: key,
        data: {
          ...newAccessKey,
          accountId: accountId
        }
      };

      this._datastore.save(entity).then(() => {
        resolve(id);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getAccessKey(accountId: string, accessKeyId: string): Promise<storage.AccessKey> {
    return q.Promise<storage.AccessKey>((resolve, reject) => {
      const key = this._datastore.key(["AccessKey", accessKeyId]);
      
      this._datastore.get(key).then(([entity]) => {
        if (!entity || entity.accountId !== accountId) {
          reject(storage.storageError(storage.ErrorCode.NotFound, `Access key ${accessKeyId} not found`));
          return;
        }
        resolve(entity);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public getAccessKeys(accountId: string): Promise<storage.AccessKey[]> {
    return q.Promise<storage.AccessKey[]>((resolve, reject) => {
      const query = this._datastore.createQuery("AccessKey")
        .filter("accountId", "=", accountId);

      this._datastore.runQuery(query).then(([entities]) => {
        resolve(entities);
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public removeAccessKey(accountId: string, accessKeyId: string): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      this.getAccessKey(accountId, accessKeyId).then(() => {
        const key = this._datastore.key(["AccessKey", accessKeyId]);
        return this._datastore.delete(key);
      }).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public updateAccessKey(accountId: string, accessKey: storage.AccessKey): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      this.getAccessKey(accountId, accessKey.id).then((existingAccessKey) => {
        const key = this._datastore.key(["AccessKey", accessKey.id]);
        const mergedAccessKey = { ...existingAccessKey, ...accessKey };
        
        const entity = {
          key: key,
          data: mergedAccessKey
        };

        return this._datastore.save(entity);
      }).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  public dropAll(): Promise<void> {
    return q.Promise<void>((resolve, reject) => {
      // Only for testing - delete all entities
      const kinds = ["Account", "App", "Deployment", "AccessKey"];
      const deletePromises = kinds.map(kind => {
        const query = this._datastore.createQuery(kind).select("__key__");
        return this._datastore.runQuery(query).then(([entities]) => {
          const keys = entities.map(entity => entity[this._datastore.KEY]);
          if (keys.length > 0) {
            return this._datastore.delete(keys);
          }
        });
      });

      Promise.all(deletePromises).then(() => {
        resolve();
      }).catch((error: any) => {
        reject(this._convertError(error));
      });
    });
  }

  private _convertError(error: any): storage.StorageError {
    if (error.code === 404) {
      return storage.storageError(storage.ErrorCode.NotFound, error.message);
    } else if (error.code === 409) {
      return storage.storageError(storage.ErrorCode.AlreadyExists, error.message);
    } else if (error.code === 403) {
      return storage.storageError(storage.ErrorCode.ConnectionFailed, "Access denied");
    } else {
      return storage.storageError(storage.ErrorCode.Other, error.message || "Unknown GCS error");
    }
  }
}