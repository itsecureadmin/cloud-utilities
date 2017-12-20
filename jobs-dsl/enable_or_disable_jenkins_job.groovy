def gitUrl = ''
def gitCredentials = ''

job("enable_or_disable_jenkins_job") {

  parameters {
    stringParam('job_identifier',    '',                      'The name of the job to enable or disable.')
    stringParam('folder_identifier', '',                      'The folder name, if applicable -- required if the job is in a folder.')
    choiceParam('enable_or_disable', [ 'enable', 'disable' ], 'Enable or disable the job.')
    stringParam('jenkins_uri',       'http://127.0.0.1:8080', 'The Jenkins service where the job is hosted.')
    stringParam('branch',            'master',                'The Git branch to use.')
  }

  logRotator (-1,30)

  scm {
    git {
      remote {
        url(gitUrl)
        credentials(gitCredentials)
      }
      branch('${branch}')
    }
  }

  steps {
    conditionalSteps {
      condition {
        stringsMatch('${folder_identifier}', '', false)
      }
      steps {
        shell('curl --silent -X POST "${jenkins_uri}/job/${job_identifier}/${enable_or_disable}"')
      }
    }
    conditionalSteps {
      condition {
        not {
          stringsMatch('${folder_identifier}', '', false)
        }
      }
      steps {
        shell('curl --silent -X POST "${jenkins_uri}/job/${folder_identifier}/job/${job_identifier}/${enable_or_disable}"')
      }
    }
  }

}
