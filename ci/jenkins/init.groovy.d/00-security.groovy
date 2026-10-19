import jenkins.model.Jenkins
import jenkins.model.JenkinsLocationConfiguration
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

// Runs once at startup (init.groovy.d). JCasC handles credentials; this
// script establishes the local admin account and the authorization strategy
// before the web UI is usable.
def env = System.getenv()
def user = env.JENKINS_ADMIN_USER ?: 'admin'
def password = env.JENKINS_ADMIN_PASSWORD
if (!password) {
    return
}

def instance = Jenkins.get()
if (!(instance.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
    def realm = new HudsonPrivateSecurityRealm(false)
    try {
        realm.createAccount(user, password)
    } catch (Exception ignored) {
        // Account may already exist after a restart.
    }
    instance.setSecurityRealm(realm)
    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)
    instance.save()
    println "security realm initialized for ${user}"
} else {
    println "security realm already initialized"
}

def location = JenkinsLocationConfiguration.get()
location.setUrl("http://127.0.0.1:8081/")
location.save()
