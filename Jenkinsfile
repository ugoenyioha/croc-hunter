#!/usr/bin/groovy

// load pipeline functions
// Requires pipeline-github-lib plugin to load library from github


def pipeline = new Pipeline()

podTemplate(label: 'jenkins-pipeline', containers: [
    containerTemplate(name: 'jnlp', image: 'lachlanevenson/jnlp-slave:3.10-1-alpine', args: '${computer.jnlpmac} ${computer.name}', workingDir: '/home/jenkins', resourceRequestCpu: '200m', resourceLimitCpu: '300m', resourceRequestMemory: '256Mi', resourceLimitMemory: '512Mi'),
    containerTemplate(name: 'docker', image: 'docker:1.12.6', command: 'cat', ttyEnabled: true),
    containerTemplate(name: 'golang', image: 'golang:1.8.3', command: 'cat', ttyEnabled: true),
    containerTemplate(name: 'helm', image: 'lachlanevenson/k8s-helm:v2.6.0', command: 'cat', ttyEnabled: true),
    containerTemplate(name: 'kubectl', image: 'lachlanevenson/k8s-kubectl:v1.4.8', command: 'cat', ttyEnabled: true),
    containerTemplate(name: 'hadolint', image: 'uenyioha/hadolint:latest', command: cat, ttyEnabled: true),
    containerTemplate(name: 'lineage', image: 'uenyioha/lineage:latest', command: cat, ttyEnabled: true)
],
volumes:[
    hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
]){

  node ('jenkins-pipeline') {

    def pwd = pwd()
    def chart_dir = "${pwd}/charts/croc-hunter"

    checkout scm

    // read in required jenkins workflow config values
    def inputFile = readFile('Jenkinsfile.json')
    def config = new groovy.json.JsonSlurperClassic().parseText(inputFile)
    println "pipeline config ==> ${config}"

    // continue only if pipeline enabled
    if (!config.pipeline.enabled) {
        println "pipeline disabled"
        return
    }

    // set additional git envvars for image tagging
    pipeline.gitEnvVars()

    // If pipeline debugging enabled
    if (config.pipeline.debug) {
      println "DEBUG ENABLED"
      sh "env | sort"

      println "Runing kubectl/helm tests"
      container('kubectl') {
        pipeline.kubectlTest()
      }
      container('helm') {
        pipeline.helmConfig()
      }
      container('hadolint') {
        pipeline.hadolintTest()
      }
      container('lineage') {
        pipeline.lineageTest()
      }
    }

    def acct = pipeline.getContainerRepoAcct(config)

    // tag image with version, and branch-commit_id
    def image_tags_map = pipeline.getContainerTags(config)

    // compile tag list
    def image_tags_list = pipeline.getMapValues(image_tags_map)

    stage ('compile and test') {

      container('golang') {
        sh "go test -v -race ./..."
        sh "make bootstrap build"
      }
    }

    stage ('test deployment') {

      container('helm') {

        // run helm chart linter
        pipeline.helmLint(chart_dir)

        // run dry-run helm chart installation
        pipeline.helmDeploy(
          dry_run       : true,
          name          : config.app.name,
          namespace     : config.app.name,
          chart_dir     : chart_dir,
          set           : [
            "imageTag": image_tags_list.get(0),
            "replicas": config.app.replicas,
            "cpu": config.app.cpu,
            "memory": config.app.memory,
            "ingress.hostname": config.app.hostname,
          ]
        )

      }
    }

    stage ('publish container') {

      container('docker') {

        // perform docker login to container registry as the docker-pipeline-plugin doesn't work with the next auth json format
        withCredentials([[$class          : 'UsernamePasswordMultiBinding', credentialsId: config.container_repo.jenkins_creds_id,
                        usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
          sh "docker login -u ${env.USERNAME} -p ${env.PASSWORD} ${config.container_repo.host}"
        }

        // build and publish container
        pipeline.containerBuildPub(
            dockerfile: config.container_repo.dockerfile,
            host      : config.container_repo.host,
            acct      : acct,
            repo      : config.container_repo.repo,
            tags      : image_tags_list,
            auth_id   : config.container_repo.jenkins_creds_id,
            image_scanning: config.container_repo.image_scanning
        )

        // anchore image scanning configuration
        // println "Add container image tags to anchore scanning list"
        
        // def tag = image_tags_list.get(0)
        // def imageLine = "${config.container_repo.host}/${acct}/${config.container_repo.repo}:${tag}" + ' ' + env.WORKSPACE + '/Dockerfile'
        // writeFile file: 'anchore_images', text: imageLine
        // anchore name: 'anchore_images', inputQueries: [[query: 'list-packages all'], [query: 'list-files all'], [query: 'cve-scan all'], [query: 'show-pkg-diffs base']]

      }

    }

    if (env.BRANCH_NAME =~ "PR-*" ) {
      stage ('deploy to k8s') {
        container('helm') {
          // Deploy using Helm chart
          pipeline.helmDeploy(
            dry_run       : false,
            name          : env.BRANCH_NAME.toLowerCase(),
            namespace     : env.BRANCH_NAME.toLowerCase(),
            chart_dir     : chart_dir,
            set           : [
              "imageTag": image_tags_list.get(0),
              "replicas": config.app.replicas,
              "cpu": config.app.cpu,
              "memory": config.app.memory,
              "ingress.hostname": config.app.hostname,
            ]
          )

          //  Run helm tests
          if (config.app.test) {
            pipeline.helmTest(
              name        : env.BRANCH_NAME.toLowerCase()
            )
          }

          // delete test deployment
          pipeline.helmDelete(
              name       : env.BRANCH_NAME.toLowerCase()
          )
        }
      }
    }

    // deploy only the master branch
    if (env.BRANCH_NAME == 'master') {
      stage ('deploy to k8s') {
        container('helm') {
          // Deploy using Helm chart
          pipeline.helmDeploy(
            dry_run       : false,
            name          : config.app.name,
            namespace     : config.app.name,
            chart_dir     : chart_dir,
            set           : [
              "imageTag": image_tags_list.get(0),
              "replicas": config.app.replicas,
              "cpu": config.app.cpu,
              "memory": config.app.memory,
              "ingress.hostname": config.app.hostname,
            ]
          )
          
          //  Run helm tests
          if (config.app.test) {
            pipeline.helmTest(
              name          : config.app.name
            )
          }
        }
      }
    }
  }
}

/***
 definitions
 **/

class Pipeline {
    def hadolintTest() {
        // Test that hadolint works
        println "checking hadolint"
        sh "hadolint"
    }
    def lineageTest() {
        // Test that lineage works
        println "checking lineage"
        sh "lineage help"
    }

    def kubectlTest() {
        // Test that kubectl can correctly communication with the Kubernetes API
        println "checking kubectl connnectivity to the API"
        sh "kubectl get nodes"
    }

    def helmLint(String chart_dir) {
        // lint helm chart
        println "running helm lint ${chart_dir}"
        sh "helm lint ${chart_dir}"

    }

    def helmConfig() {
        //setup helm connectivity to Kubernetes API and Tiller
        println "initiliazing helm client"
        sh "helm init --service-account default"
        println "checking client/server version"
        sh "helm version"
    }


    def helmDeploy(Map args) {
        //configure helm client and confirm tiller process is installed
        helmConfig()

        def String namespace

        // If namespace isn't parsed into the function set the namespace to the name
        if (args.namespace == null) {
            namespace = args.name
        } else {
            namespace = args.namespace
        }

        if (args.dry_run) {
            println "Running dry-run deployment"

            sh "helm upgrade --dry-run --install --force ${args.name} ${args.chart_dir} --set imageTag=${args.version_tag},replicas=${args.replicas},cpu=${args.cpu},memory=${args.memory},ingress.hostname=${args.hostname} --namespace=${namespace}"
        } else {
            println "Running deployment"

            // reimplement --wait once it works reliable
            sh "helm upgrade --install --force ${args.name} ${args.chart_dir} --set imageTag=${args.version_tag},replicas=${args.replicas},cpu=${args.cpu},memory=${args.memory},ingress.hostname=${args.hostname} --namespace=${namespace}"

            // sleeping until --wait works reliably
            sleep(20)

            echo "Application ${args.name} successfully deployed. Use helm status ${args.name} to check"
        }
    }

    def helmDelete(Map args) {
        println "Running helm delete ${args.name}"

        sh "helm delete ${args.name}"
    }

    def helmTest(Map args) {
        println "Running Helm test"

        sh "helm test ${args.name} --cleanup"
    }

    def gitEnvVars() {
        // create git envvars
        println "Setting envvars to tag container"

        sh 'git rev-parse HEAD > git_commit_id.txt'
        try {
            env.GIT_COMMIT_ID = readFile('git_commit_id.txt').trim()
            env.GIT_SHA = env.GIT_COMMIT_ID.substring(0, 7)
        } catch (e) {
            error "${e}"
        }
        println "env.GIT_COMMIT_ID ==> ${env.GIT_COMMIT_ID}"

        sh 'git config --get remote.origin.url> git_remote_origin_url.txt'
        try {
            env.GIT_REMOTE_URL = readFile('git_remote_origin_url.txt').trim()
        } catch (e) {
            error "${e}"
        }
        println "env.GIT_REMOTE_URL ==> ${env.GIT_REMOTE_URL}"
    }


    def containerBuildPub(Map args) {

        println "Running Docker build/publish: ${args.host}/${args.acct}/${args.repo}:${args.tags}"

        docker.withRegistry("https://${args.host}", "${args.auth_id}") {

            // def img = docker.build("${args.acct}/${args.repo}", args.dockerfile)
            def img = docker.image("${args.acct}/${args.repo}")
            sh "docker build --build-arg VCS_REF=${env.GIT_SHA} --build-arg BUILD_DATE=`date -u +'%Y-%m-%dT%H:%M:%SZ'` -t ${args.acct}/${args.repo} ${args.dockerfile}"
            for (int i = 0; i < args.tags.size(); i++) {
                img.push(args.tags.get(i))
            }

            return img.id
        }
    }

    def getContainerTags(config, Map tags = [:]) {

        println "getting list of tags for container"
        def String commit_tag
        def String version_tag

        try {
            // if PR branch tag with only branch name
            if (env.BRANCH_NAME.contains('PR')) {
                commit_tag = env.BRANCH_NAME
                tags << ['commit': commit_tag]
                return tags
            }
        } catch (Exception e) {
            println "WARNING: commit unavailable from env. ${e}"
        }

        // commit tag
        try {
            // if branch available, use as prefix, otherwise only commit hash
            if (env.BRANCH_NAME) {
                commit_tag = env.BRANCH_NAME + '-' + env.GIT_COMMIT_ID.substring(0, 7)
            } else {
                commit_tag = env.GIT_COMMIT_ID.substring(0, 7)
            }
            tags << ['commit': commit_tag]
        } catch (Exception e) {
            println "WARNING: commit unavailable from env. ${e}"
        }

        // master tag
        try {
            if (env.BRANCH_NAME == 'master') {
                tags << ['master': 'latest']
            }
        } catch (Exception e) {
            println "WARNING: branch unavailable from env. ${e}"
        }

        // build tag only if none of the above are available
        if (!tags) {
            try {
                tags << ['build': env.BUILD_TAG]
            } catch (Exception e) {
                println "WARNING: build tag unavailable from config.project. ${e}"
            }
        }

        return tags
    }

    def getContainerRepoAcct(config) {

        println "setting container registry creds according to Jenkinsfile.json"
        def String acct

        if (env.BRANCH_NAME == 'master') {
            acct = config.container_repo.master_acct
        } else {
            acct = config.container_repo.alt_acct
        }

        return acct
    }

    @NonCPS
    def getMapValues(Map map=[:]) {
        // jenkins and workflow restriction force this function instead of map.values(): https://issues.jenkins-ci.org/browse/JENKINS-27421
        def entries = []
        def map_values = []

        entries.addAll(map.entrySet())

        for (int i=0; i < entries.size(); i++){
            String value =  entries.get(i).value
            map_values.add(value)
        }

        return map_values
    }
}

