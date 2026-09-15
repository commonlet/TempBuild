import * as glob from '@actions/glob'  
import * as path from 'path'  
import { stat } from 'fs/promises'  
import artifact, { ArtifactNotFoundError } from '@actions/artifact'  
import { dirname } from 'path'  
  
const [,, artifactName, searchPath, retentionDaysArg, compressionLevelArg, overwriteArg, ifNoFilesFoundArg, includeHiddenFilesArg] = process.argv  
  
const overwrite = overwriteArg === 'true'  
const ifNoFilesFound = ifNoFilesFoundArg || 'warn'  
const includeHiddenFiles = includeHiddenFilesArg === 'true'  
  
function getMultiPathLCA(searchPaths)  
{  
  if (searchPaths.length < 2)  
  {  
    throw new Error('At least two search paths must be provided')  
  }  
  
  const commonPaths = []  
  const splitPaths = []  
  let smallestPathLength = Number.MAX_SAFE_INTEGER  
  
  for (const searchPath of searchPaths)  
  {  
    const splitSearchPath = path.normalize(searchPath).split(path.sep)  
    smallestPathLength = Math.min(smallestPathLength, splitSearchPath.length)  
    splitPaths.push(splitSearchPath)  
  }  
  
  if (searchPaths[0].startsWith(path.sep))  
  {  
    commonPaths.push(path.sep)  
  }  
  
  let splitIndex = 0  
  
  function isPathTheSame()  
  {  
    const compare = splitPaths[0][splitIndex]  
    for (let i = 1; i < splitPaths.length; i++)  
    {  
      if (compare !== splitPaths[i][splitIndex]) return false  
    }  

    return true  
  }  
  
  while (splitIndex < smallestPathLength)  
  {  
    if (!isPathTheSame()) break  
    commonPaths.push(splitPaths[0][splitIndex])  
    splitIndex++  
  }  
  
  return path.join(...commonPaths)  
}  
  
async function findFilesToUpload(searchPath, includeHiddenFiles = false)  
{  
  const globber = await glob.create(  
    searchPath,  
    {  
      followSymbolicLinks: true,  
      implicitDescendants: true,  
      omitBrokenSymbolicLinks: true,  
      excludeHiddenFiles: !includeHiddenFiles  
    }  
  )  
  
  const raw = await globber.glob()  
  const filesToUpload = []  
  const set = new Set()  
  
  for (const p of raw)  
  {  
    if (!(await stat(p)).isDirectory())  
    {  
      filesToUpload.push(p)  
  
      if (set.has(p.toLowerCase()))  
      {  
        console.log(`Uploads are case insensitive: ${p} was detected that it will be overwritten by another file with the same path`)  
      }  
      else  
      {  
        set.add(p.toLowerCase())  
      }  
    }  
  }  
  
  const searchPaths = globber.getSearchPaths()  
  
  if (searchPaths.length > 1)  
  {  
    console.log('Multiple search paths detected. Calculating the least common ancestor of all paths')  
    const lcaSearchPath = getMultiPathLCA(searchPaths)  
    console.log(`The least common ancestor is ${lcaSearchPath}. This will be the root directory of the artifact`)  
    return { filesToUpload, rootDirectory: lcaSearchPath }  
  }  
  
  if (filesToUpload.length === 1 && searchPaths[0] === filesToUpload[0])  
  {  
    return { filesToUpload, rootDirectory: dirname(filesToUpload[0]) }  
  }  
  
  return { filesToUpload, rootDirectory: searchPaths[0] }  
}  
  
async function deleteArtifactIfExists(artifactName)  
{  
  try  
  {  
    await artifact.deleteArtifact(artifactName)  
  }  
  catch (error)  
  {  
    if (error instanceof ArtifactNotFoundError)  
    {  
      console.log(`Skipping deletion of '${artifactName}', it does not exist`)  
      return  
    }  
  
    console.log(`Unable to delete artifact: ${error.message}`)  
  }  
}  
  
const { filesToUpload, rootDirectory } = await findFilesToUpload(searchPath, includeHiddenFiles)  
  
if (filesToUpload.length === 0)  
{  
  switch (ifNoFilesFound)  
  {  
    case 'warn':  
      console.log(`No files were found with the provided path: ${searchPath}. No artifacts will be uploaded.`)  
      break  
    case 'error':  
      console.error(`No files were found with the provided path: ${searchPath}. No artifacts will be uploaded.`)  
      process.exit(1)  
    case 'ignore':  
      console.log(`No files were found with the provided path: ${searchPath}. No artifacts will be uploaded.`)  
      break  
  }  
  
  process.exit(0)  
}  
  
console.log(`With the provided path, there will be ${filesToUpload.length} file(s) uploaded`)  
console.log(`Root artifact directory is ${rootDirectory}`)  
  
if (overwrite)  
{  
  await deleteArtifactIfExists(artifactName)  
}  
  
const options = {}  
if (retentionDaysArg) options.retentionDays = parseInt(retentionDaysArg)  
if (compressionLevelArg) options.compressionLevel = parseInt(compressionLevelArg)  
  
const result = await artifact.uploadArtifact(artifactName, filesToUpload, rootDirectory, options)  
  
console.log(`Artifact ${artifactName} has been successfully uploaded! Final size is ${result.size} bytes. Artifact ID is ${result.id}`)  
  
const artifactURL = `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}/artifacts/${result.id}`  
console.log(`Artifact download URL: ${artifactURL}`)  
  
console.log(`Uploaded! id=${result.id} size=${result.size} digest=${result.digest}`)
