#!/usr/bin/env node

const { program } = require('commander');
const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const BAYANAT_REPO_URL = 'https://github.com/sjacorg/bayanat.git';

// Helper functions
function getCurrentUser() {
  try {
    const username = execSync('whoami', { encoding: 'utf-8' }).trim();
    const isRoot = username === 'root';
    
    let hasSudo = false;
    try {
      execSync('sudo -n true', { stdio: 'ignore' });
      hasSudo = true;
    } catch {}
    
    return {
      username,
      isRoot,
      hasSudo,
      isBayanatUser: username === 'bayanat',
      isAdminUser: ['ubuntu', 'root'].includes(username) || hasSudo
    };
  } catch (error) {
    console.error('Error getting user info:', error.message);
    process.exit(1);
  }
}

function runCommand(command, options = {}) {
  try {
    const result = execSync(command, { 
      encoding: 'utf-8', 
      stdio: options.silent ? 'pipe' : 'inherit',
      ...options 
    });
    return result;
  } catch (error) {
    console.error(`Error running command: ${command}`);
    console.error(error.message);
    process.exit(1);
  }
}

function checkUserPermissions(command) {
  const user = getCurrentUser();
  
  // App installation can be run by bayanat user in their directory
  if (command === 'install' && !user.isAdminUser && !user.isBayanatUser) {
    console.error('❌ Application installation requires admin or bayanat user privileges');
    console.error('Please run as root, admin user, or switch to bayanat user: sudo su - bayanat');
    return false;
  }
  
  if (command === 'update' && !user.isBayanatUser && !user.isAdminUser) {
    console.error('❌ Updates should be run as the bayanat user');
    console.error('Switch to bayanat user: sudo su - bayanat');
    return false;
  }
  
  return true;
}

function restartServices(serviceName = 'bayanat') {
  console.log('🔄 Restarting services...');
  const user = getCurrentUser();
  
  try {
    // Restart main service
    const cmd = user.isBayanatUser ? 
      `sudo systemctl restart ${serviceName}` : 
      `systemctl restart ${serviceName}`;
    
    runCommand(cmd, { silent: true });
    console.log(`✅ Successfully restarted ${serviceName} service`);
    
    // Restart celery service if exists
    const celeryService = `${serviceName}-celery`;
    const celeryCmd = user.isBayanatUser ? 
      `sudo systemctl restart ${celeryService}` : 
      `systemctl restart ${celeryService}`;
    
    try {
      runCommand(celeryCmd, { silent: true });
      console.log(`✅ Successfully restarted ${celeryService} service`);
    } catch {
      console.log(`⚠️  ${celeryService} service not found or failed to restart`);
    }
    
    return true;
  } catch (error) {
    console.error('❌ Failed to restart services:', error.message);
    return false;
  }
}

function createEnvironmentConfig(appDir) {
  try {
    // Check if .env already exists
    const envPath = path.join(appDir, '.env');
    if (fs.existsSync(envPath)) {
      console.log('✅ Environment file already exists');
      return;
    }

    // Use Bayanat's gen-env.sh script for proper secrets
    try {
      runCommand('./gen-env.sh -n -o', { cwd: appDir, silent: true });
      console.log('✅ Environment generated with proper secrets');
      
      // Append database and Redis configuration
      const dbConfig = `
# Database (convention-based)
DATABASE_URL=postgresql://bayanat@localhost/bayanat

# Redis
REDIS_URL=redis://localhost:6379/0
`;
      fs.appendFileSync(envPath, dbConfig);
      console.log('✅ Database configuration added');
      
    } catch {
      // Fallback if gen-env.sh doesn't exist
      console.log('📝 Creating basic environment configuration...');
      
      const envContent = `FLASK_APP=run.py
FLASK_DEBUG=0

# Database (convention-based)
DATABASE_URL=postgresql://bayanat@localhost/bayanat

# Redis
REDIS_URL=redis://localhost:6379/0

# Security (generate your own keys for production)
SECRET_KEY=change-this-in-production
SECURITY_PASSWORD_SALT=change-this-in-production
SECURITY_TOTP_SECRETS=change-this-in-production
SECURITY_TWO_FACTOR=True
`;
      
      fs.writeFileSync(envPath, envContent);
      console.log('✅ Basic environment configuration created');
    }
    
    // Set proper permissions
    runCommand(`chmod 640 ${envPath}`);
    
  } catch (error) {
    console.log('⚠️  Could not create environment file:', error.message);
  }
}

function setupSystemdServices(appDir) {
  try {
    // Create main service file
    const mainService = `[Unit]
Description=Bayanat Application
After=network.target postgresql.service redis.service

[Service]
User=bayanat
Group=bayanat
WorkingDirectory=${appDir}
EnvironmentFile=${appDir}/.env
ExecStart=${appDir}/env/bin/uwsgi --ini uwsgi.ini
Restart=always
RestartSec=3
StartLimitIntervalSec=0

# Security Hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=${appDir}

[Install]
WantedBy=multi-user.target
`;

    // Create celery service file
    const celeryService = `[Unit]
Description=Bayanat Celery Service
After=network.target redis.service

[Service]
User=bayanat
Group=bayanat
WorkingDirectory=${appDir}
Environment="PATH=${appDir}/env/bin:/usr/bin"
EnvironmentFile=${appDir}/.env
ExecStart=${appDir}/env/bin/celery -A enferno.tasks worker --autoscale 2,5 -B
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
`;

    // Write service files (requires admin privileges)
    runCommand(`echo '${mainService}' | sudo tee /etc/systemd/system/bayanat.service > /dev/null`);
    runCommand(`echo '${celeryService}' | sudo tee /etc/systemd/system/bayanat-celery.service > /dev/null`);
    
    // Enable and start services
    runCommand('sudo systemctl daemon-reload');
    runCommand('sudo systemctl enable bayanat bayanat-celery');
    runCommand('sudo systemctl start bayanat bayanat-celery');
    
    console.log('✅ Systemd services created and started');
    
    // Show status
    setTimeout(() => {
      try {
        console.log('\n📊 Service Status:');
        runCommand('sudo systemctl status bayanat --no-pager -l', { silent: false });
      } catch (error) {
        console.log('⚠️  Check service status with: systemctl status bayanat');
      }
    }, 2000);
    
  } catch (error) {
    console.log('⚠️  Could not auto-setup services (requires admin privileges)');
    console.log('💡 Run as admin or manually create systemd services');
  }
}

function showRoleBasedHelp() {
  const user = getCurrentUser();
  
  console.log('🚀 Bayanat CLI - Production Management Tool\n');
  
  if (user.isBayanatUser) {
    console.log('👤 Running as bayanat user (service account)');
    console.log('Available commands:');
    console.log('• bayanat update - Update application and restart services');
    console.log('• bayanat restart - Restart services only');
    console.log('• bayanat backup - Create database backup');
    console.log('• bayanat version - Check current version');
    console.log('\n💡 Services restart automatically after updates!');
  } else if (user.isAdminUser) {
    console.log('👑 Running as admin user (privileged)');
    console.log('Available commands:');
    console.log('• bayanat install - Full system installation');
    console.log('• sudo systemctl restart bayanat - Restart services');
    console.log('• sudo systemctl status bayanat - Check service status');
    console.log('\n💡 Note: For code updates, switch to bayanat user:');
    console.log('   sudo su - bayanat');
    console.log('   bayanat update');
  } else {
    console.log('❌ Unknown user role');
    console.log('This CLI is designed for:');
    console.log('• bayanat user: Application management');
    console.log('• ubuntu/root users: System administration');
  }
}

// Commands
program
  .name('bayanat')
  .description('CLI tool for Bayanat data management system')
  .version('0.1.0')
  .action(() => {
    showRoleBasedHelp();
    console.log('\nUse bayanat --help to see all available commands.');
  });

program
  .command('install')
  .description('Install the Bayanat application in the current directory')
  .option('--force', 'Force installation even if directory is not empty')
  .option('--skip-system', 'Skip system dependencies installation')
  .action((options) => {
    if (!checkUserPermissions('install')) process.exit(1);
    
    const appDir = process.cwd();
    console.log(`🚀 Installing Bayanat in: ${appDir}`);
    
    try {
      // Check if directory is empty
      if (!options.force && fs.readdirSync(appDir).length > 0) {
        console.error(`❌ Directory '${appDir}' is not empty. Use --force to override.`);
        process.exit(1);
      }
      
      // Clone repository directly to current directory
      console.log('📦 Cloning Bayanat repository...');
      runCommand(`git clone ${BAYANAT_REPO_URL} .`);
      
      // Create virtual environment
      console.log('🐍 Setting up Python environment...');
      runCommand(`python3 -m venv ${path.join(appDir, 'env')}`);
      
      // Install dependencies
      console.log('📚 Installing dependencies...');
      const pipPath = path.join(appDir, 'env', 'bin', 'pip');
      runCommand(`${pipPath} install --upgrade pip`);
      runCommand(`${pipPath} install -r ${path.join(appDir, 'requirements', 'main.txt')}`);
      
      // Create environment configuration
      console.log('📝 Creating environment configuration...');
      createEnvironmentConfig(appDir);
      
      // Create CLI metadata with conventions
      const metadata = {
        version: '0.1.0',
        installed_at: new Date().toISOString(),
        installation_type: 'production',
        database_url: 'postgresql://bayanat@localhost/bayanat'
      };
      fs.writeFileSync(path.join(appDir, '.bayanat-cli'), JSON.stringify(metadata, null, 2));
      
      // Auto-setup systemd services
      console.log('⚙️  Setting up systemd services...');
      setupSystemdServices(appDir);
      
      console.log('🎉 Bayanat installation completed successfully!');
      console.log('✅ Services are running and ready to use!');
      console.log(`Run 'bayanat update' from ${appDir} to update in the future.`);
      
    } catch (error) {
      console.error('❌ Installation failed:', error.message);
      process.exit(1);
    }
  });

program
  .command('update')
  .description('Update the Bayanat application')
  .option('--skip-git', 'Skip Git operations')
  .option('--skip-deps', 'Skip dependency installation')
  .option('--skip-restart', 'Skip service restart')
  .option('--force', 'Force update even if already up-to-date')
  .action((options) => {
    if (!checkUserPermissions('update')) process.exit(1);
    
    const appDir = process.cwd();
    
    try {
      console.log('🔄 Updating Bayanat...');
      
      if (!options.skipGit) {
        console.log('📦 Fetching latest code...');
        runCommand('git fetch', { cwd: appDir });
        runCommand('git pull', { cwd: appDir });
      }
      
      if (!options.skipDeps) {
        console.log('📚 Installing dependencies...');
        const pipPath = path.join(appDir, 'env', 'bin', 'pip');
        runCommand(`${pipPath} install -r ${path.join(appDir, 'requirements', 'main.txt')}`);
      }
      
      if (!options.skipRestart) {
        restartServices();
      }
      
      console.log('🎉 Update completed successfully!');
      console.log('✅ Services restarted automatically - changes are now live!');
      
    } catch (error) {
      console.error('❌ Update failed:', error.message);
      process.exit(1);
    }
  });

program
  .command('restart')
  .description('Restart Bayanat services')
  .option('--service <name>', 'Service name to restart', 'bayanat')
  .action((options) => {
    const user = getCurrentUser();
    
    if (!user.isAdminUser && !user.isBayanatUser) {
      console.error('❌ Service restart requires appropriate privileges');
      process.exit(1);
    }
    
    if (restartServices(options.service)) {
      console.log('🎉 Services restarted successfully!');
    } else {
      process.exit(1);
    }
  });

program
  .command('backup')
  .description('Create a database backup')
  .option('-o, --output <file>', 'Output file path')
  .action((options) => {
    console.log('💾 Creating database backup...');
    // This would call the Flask backup command
    console.log('Database backup functionality needs Flask integration');
  });

program
  .command('version')
  .description('Display version information')
  .action(() => {
    console.log('Bayanat CLI version: 0.1.0');
    // This would check the actual Bayanat version from pyproject.toml
  });

// Handle case when no command is provided
if (process.argv.length === 2) {
  showRoleBasedHelp();
  console.log('\nUse bayanat --help to see all available commands.');
}

program.parse();