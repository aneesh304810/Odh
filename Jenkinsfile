// Jenkinsfile
//
// Pipeline that builds the ODH Code Server + Airflow + dbt image on
// OpenShift and publishes it to the ODH dashboard ImageStream.
//
// Flow:
//   1. Checkout     – pull this repo at the requested ref
//   2. Apply        – ensure the BuildConfig / ImageStream exist
//   3. Build        – oc start-build, stream logs, wait for completion
//   4. Smoke Test   – spin up the image briefly to confirm entrypoint works
//   5. Tag          – tag the :latest output to the version + to the
//                     dashboard namespace so developers can pick it up
//   6. Promote      – (optional, main branch only) tag into the dashboard
//                     ImageStream in redhat-ods-applications
//
// Requires:
//   - Jenkins running on OpenShift with the OpenShift Client plugin
//   - ServiceAccount `jenkins` in namespace BUILD_NAMESPACE has `edit`
//     on BUILD_NAMESPACE and `edit` on DASHBOARD_NAMESPACE
//   - Optional: `git-creds` secret in BUILD_NAMESPACE for private repos

pipeline {
    agent {
        // Run on the Jenkins OpenShift agent. 'maven' or 'nodejs' agents
        // work; we just need `oc` and `git`. The default jenkins-agent-base
        // image has both.
        label 'jenkins-agent-base'
    }

    options {
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
        disableConcurrentBuilds()
        ansiColor('xterm')
        timestamps()
    }

    parameters {
        string(
            name: 'GIT_REF',
            defaultValue: 'main',
            description: 'Branch, tag, or commit SHA to build'
        )
        string(
            name: 'IMAGE_TAG',
            defaultValue: '',
            description: 'Image tag (leave blank to auto-derive from GIT_REF + build number)'
        )
        booleanParam(
            name: 'PROMOTE_TO_DASHBOARD',
            defaultValue: false,
            description: 'After a successful build, tag into redhat-ods-applications so the ODH dashboard picks it up'
        )
        booleanParam(
            name: 'SKIP_SMOKE_TEST',
            defaultValue: false,
            description: 'Skip the post-build smoke test (faster, less safe)'
        )
    }

    environment {
        BUILD_NAMESPACE     = 'odh-images'
        DASHBOARD_NAMESPACE = 'redhat-ods-applications'
        BUILDCONFIG_NAME    = 'codeserver-airflow-dbt'
        IMAGESTREAM_NAME    = 'codeserver-airflow-dbt'
    }

    stages {

        // --------------------------------------------------------------
        stage('Checkout') {
            steps {
                script {
                    // Allow the pipeline to be parameterized on any ref.
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: params.GIT_REF]],
                        userRemoteConfigs: [[
                            url: 'https://github.com/aneesh304810/Odh.git',
                            credentialsId: 'github-pat'
                        ]]
                    ])

                    // Derive image tag if not provided. Priority:
                    //   1. User-supplied IMAGE_TAG
                    //   2. Git tag (if HEAD is tagged)
                    //   3. <branch>-<short-sha>-b<build>
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    def gitTag = sh(
                        script: 'git tag --points-at HEAD | head -n1',
                        returnStdout: true
                    ).trim()

                    if (params.IMAGE_TAG?.trim()) {
                        env.RESOLVED_TAG = params.IMAGE_TAG.trim()
                    } else if (gitTag) {
                        env.RESOLVED_TAG = gitTag
                    } else {
                        def safeBranch = params.GIT_REF
                            .replaceAll('[^a-zA-Z0-9._-]', '-')
                            .toLowerCase()
                        env.RESOLVED_TAG = "${safeBranch}-${env.GIT_SHA}-b${env.BUILD_NUMBER}"
                    }

                    echo "Resolved image tag: ${env.RESOLVED_TAG}"
                    currentBuild.description = "${params.GIT_REF} → ${env.RESOLVED_TAG}"
                }
            }
        }

        // --------------------------------------------------------------
        stage('Lint') {
            steps {
                script {
                    // Dockerfile lint — non-blocking for now, tighten later.
                    sh '''
                        if command -v hadolint >/dev/null 2>&1; then
                            hadolint --no-fail container/Dockerfile || true
                        else
                            echo "hadolint not installed on agent, skipping"
                        fi
                    '''
                    // Shell lint
                    sh '''
                        if command -v shellcheck >/dev/null 2>&1; then
                            shellcheck -S warning scripts/*.sh || true
                        fi
                    '''
                    // Validate YAML manifests
                    sh '''
                        for f in $(find manifests -name "*.yaml" -o -name "*.yml"); do
                            python3 -c "import sys, yaml; list(yaml.safe_load_all(open('$f')))" \
                                && echo "ok  $f" || { echo "bad $f"; exit 1; }
                        done
                    '''
                }
            }
        }

        // --------------------------------------------------------------
        stage('Apply OpenShift resources') {
            steps {
                script {
                    openshift.withCluster() {
                        openshift.withProject(env.BUILD_NAMESPACE) {
                            // Apply the ImageStream + BuildConfig via kustomize.
                            // `oc apply -k` is idempotent; safe to re-run.
                            sh "oc apply -k manifests/build/ -n ${env.BUILD_NAMESPACE}"

                            // Sanity check: both resources exist.
                            def bc = openshift.selector('bc', env.BUILDCONFIG_NAME)
                            if (!bc.exists()) {
                                error "BuildConfig ${env.BUILDCONFIG_NAME} missing after apply"
                            }
                            def is = openshift.selector('is', env.IMAGESTREAM_NAME)
                            if (!is.exists()) {
                                error "ImageStream ${env.IMAGESTREAM_NAME} missing after apply"
                            }
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------------
        stage('Build image') {
            steps {
                script {
                    openshift.withCluster() {
                        openshift.withProject(env.BUILD_NAMESPACE) {
                            // Patch the BuildConfig source ref to match the
                            // checked-out ref, so the build pulls the same
                            // commit the pipeline just validated.
                            openshift.raw(
                                "patch bc/${env.BUILDCONFIG_NAME}",
                                "--type=merge",
                                "-p", "'{\"spec\":{\"source\":{\"git\":{\"ref\":\"${env.GIT_SHA}\"}}}}'"
                            )

                            echo "Starting build of ${env.BUILDCONFIG_NAME} at ref ${env.GIT_SHA}"
                            def build = openshift.selector('bc', env.BUILDCONFIG_NAME)
                                .startBuild("--commit=${env.GIT_SHA}")

                            // Stream logs to Jenkins console.
                            build.logs('-f')

                            // Wait and check status.
                            timeout(time: 30, unit: 'MINUTES') {
                                build.untilEach(1) {
                                    def phase = it.object().status.phase
                                    echo "Build phase: ${phase}"
                                    return phase in ['Complete', 'Failed', 'Error', 'Cancelled']
                                }
                            }

                            def phase = build.object().status.phase
                            if (phase != 'Complete') {
                                error "Build ended with phase=${phase}"
                            }

                            // Capture the digest for downstream tagging.
                            env.IMAGE_DIGEST = build.object()
                                .status.output.to.imageDigest
                            echo "Built image digest: ${env.IMAGE_DIGEST}"
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------------
        stage('Tag version') {
            steps {
                script {
                    openshift.withCluster() {
                        openshift.withProject(env.BUILD_NAMESPACE) {
                            // Tag :latest -> :<resolved-tag> in the same
                            // ImageStream so we have an immutable reference.
                            sh """
                                oc tag \
                                    ${env.IMAGESTREAM_NAME}:latest \
                                    ${env.IMAGESTREAM_NAME}:${env.RESOLVED_TAG} \
                                    -n ${env.BUILD_NAMESPACE}
                            """
                            echo "Tagged ${env.IMAGESTREAM_NAME}:${env.RESOLVED_TAG}"
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------------
        stage('Smoke test') {
            when {
                expression { return !params.SKIP_SMOKE_TEST }
            }
            steps {
                script {
                    openshift.withCluster() {
                        openshift.withProject(env.BUILD_NAMESPACE) {
                            // Spin the image up briefly to confirm the
                            // entrypoint doesn't crash. We don't need Airflow
                            // to be fully functional here — just verify the
                            // container starts and the critical binaries are
                            // on PATH.
                            def podName = "smoke-${env.BUILD_NUMBER}"
                            def imgRef  = "image-registry.openshift-image-registry.svc:5000/${env.BUILD_NAMESPACE}/${env.IMAGESTREAM_NAME}:${env.RESOLVED_TAG}"

                            sh """
                                oc run ${podName} \
                                    --image=${imgRef} \
                                    --restart=Never \
                                    --rm -i \
                                    --command -- /bin/bash -c '
                                        set -e
                                        echo "=== Binaries ==="
                                        which airflow && airflow version
                                        which dbt && dbt --version
                                        which python && python --version
                                        echo "=== Oracle IC ==="
                                        ls /opt/oracle/instantclient/libclntsh.so*
                                        echo "=== Entry point (dry run) ==="
                                        START_AIRFLOW=false /opt/scripts/entrypoint.sh echo entrypoint-ok
                                        echo "SMOKE_OK"
                                    ' \
                                    -n ${env.BUILD_NAMESPACE}
                            """
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------------
        stage('Promote to ODH dashboard') {
            when {
                expression { return params.PROMOTE_TO_DASHBOARD }
            }
            steps {
                script {
                    openshift.withCluster() {
                        // Cross-namespace tag. The Jenkins SA needs
                        // system:image-puller in BUILD_NAMESPACE and
                        // permission to update imagestreamtags in
                        // DASHBOARD_NAMESPACE.
                        sh """
                            oc tag \
                                ${env.BUILD_NAMESPACE}/${env.IMAGESTREAM_NAME}:${env.RESOLVED_TAG} \
                                ${env.DASHBOARD_NAMESPACE}/${env.IMAGESTREAM_NAME}:${env.RESOLVED_TAG} \
                                --reference-policy=local

                            oc tag \
                                ${env.BUILD_NAMESPACE}/${env.IMAGESTREAM_NAME}:${env.RESOLVED_TAG} \
                                ${env.DASHBOARD_NAMESPACE}/${env.IMAGESTREAM_NAME}:latest \
                                --reference-policy=local
                        """
                        echo "Promoted ${env.RESOLVED_TAG} to ${env.DASHBOARD_NAMESPACE}"
                    }
                }
            }
        }
    }

    post {
        success {
            echo """
            ================================================================
            Build SUCCEEDED
              Tag:     ${env.RESOLVED_TAG}
              Commit:  ${env.GIT_SHA}
              Image:   image-registry.openshift-image-registry.svc:5000/${env.BUILD_NAMESPACE}/${env.IMAGESTREAM_NAME}:${env.RESOLVED_TAG}
              Promoted: ${params.PROMOTE_TO_DASHBOARD}
            ================================================================
            """
        }
        failure {
            echo "Build FAILED at stage: ${env.STAGE_NAME}"
            // Pull the last 200 lines of build logs for debugging.
            script {
                try {
                    openshift.withCluster() {
                        openshift.withProject(env.BUILD_NAMESPACE) {
                            sh "oc logs bc/${env.BUILDCONFIG_NAME} --tail=200 || true"
                        }
                    }
                } catch (e) {
                    echo "Couldn't fetch build logs: ${e.message}"
                }
            }
        }
        cleanup {
            cleanWs()
        }
    }
}
