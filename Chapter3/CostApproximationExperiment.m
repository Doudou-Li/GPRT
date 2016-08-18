% This file contains the cost experiments of Chapter 3 of the Gaussian process regression thesis. We take the pitch-plunge system and approximate its cost function.
% To use it, make sure that the Matlab directory is set to the directory of this file. Then you can run this file. You have to run this file all in one go. (Press the F5 button or call
% "CostApproximationExperiment" from the Matlab command line.) Separate blocks cannot be run independently anymore, because this would really result in too many duplicate scripts.

% We set up the workspace, ready for executing scripts.
clear all; % Empty the workspace.
clc; % Empty the command window.
exportFigs = 1; % Do we export figures? 0 for no, 1 (or anything else) for yes.
useColor = 1; % Should we set up plots for colored output (1) or black-and-white output (0)?

% We add paths containing files which we will need.
addpath('../PitchPlunge/Definitions/');
addpath('../PitchPlunge/Controllers/');
addpath('../ExportFig/');
addpath('../Tools/');

% Next, it's time to gather data for GP regression. We set the number of measurements that we want to do.
nm = 50; % We set the number of time steps we want to feed to the GP. (Note that later on we do full simulations, so I would not recommend setting nm larger than 1000 unless you're really patient.)
Xm = zeros(4,2*nm); % This set will contain all input data.
rb = zeros(nm,1); % This set will contain all output data.

% To start off, we define timing data.
dt = 0.001; % We define the simulation time step.
T = 1; % We define the simulation length.
numDataPoints = ceil(T/dt)+1; % We calculate the number of data points we'll be having.
t = 0:dt:T; % This is the time array.

% We also set up other parameters. These are set to default values.
defineFlow; % We set up the flow properties.
defineStructuralParameters; % We define the structural parameters.
defineInitialConditions; % We define the initial conditions.
defineControllerParameters; % We set up the controller parameters.

% We define the range for the initial state and the control input.
h0Range = 5e-3;
a0Range = 6e-2;
hd0Range = 5e-2;
ad0Range = 1e0;
betaRange = 5e-1;
useNonlinear = 0; % We indicate we use the linear model for now.

% We set a few important system parameters.
U0 = 10; % We pick a wind speed of 10 m/s, ensuring we at least have a stable system for reasonable controllers.

% We define the cost function parameters.
Q = zeros(4,4);
Q(3,3) = 1/hd0Range^2;
Q(4,4) = 1/ad0Range^2;
R = 4/betaRange^2;
gamma = 0.5;
a = (1/2)*log(gamma); % This is the alpha parameter from the LQG cost function. We have gamma^T = e^(2*a*T).

% We set up helpful matrices.
I = eye(4); % The identity matrix I.
Z = zeros(4,4); % The zero matrix 0.

% We set up the discrete-time matrices for the linearized pitch-plunge system. These can be used so we don't have to run the Simulink simulation for the linear model, which saves us time.
applySettings; % We apply the settings which have been set so far, also taking into account any possible adjustments that have been made. This also defines system matrices.
sysA = [zeros(2,2), eye(2); -M\(K+U0^2*D), -M\(C+U0*E)]; % This is the system A matrix.
sysB = [zeros(2,1); M\(U0^2*F)]; % This is the system B matrix.

% We define which controller we will use.
controller = @stateController;
global hGain alphaGain hDotGain alphaDotGain;
hGain = 0;
alphaGain = 0;
hDotGain = 0;
alphaDotGain = 0;
sysF = [hGain,alphaGain,hDotGain,alphaDotGain]; % This is the matrix \tilde{F}.

% % Optionally, we set the controller to the optimal LQG controller.
% X = are(sysA + a*I, sysB/R*sysB', Q);
% sysF = R\sysB'*X;
% hGain = sysF(1);
% alphaGain = sysF(2);
% hDotGain = sysF(3);
% alphaDotGain = sysF(4);

% We now set up related system matrices.
At = sysA - sysB*sysF; % This is the matrix \tilde{A} = A - B*F.
Qt = Q + sysF'*R*sysF; % This is the matrix \tilde{Q} = Q + F^T*R*F.
Ad = expm(At*T); % This is the discrete-time system matrix.
Xb = lyap((At+a*eye(4))', -Qt); % This is the matrix Xb which we eventually want to approximate. We add the minus sign here because we use negative rewards. As a result, the value will be negative.

% We now loop through the experiments to obtain data.
rng(1, 'twister'); % We fix Matlab's random number generator, so that it always creates functions which I've found to be pretty representative as far as random samples go.
for experiment = 1:nm
	% We set the initial state for the simulation.
	h0 = (rand(1,1)*2-1)*h0Range; % Initial plunge. [m]
	a0 = (rand(1,1)*2-1)*a0Range; % Initial pitch angle. [rad]
	hd0 = (rand(1,1)*2-1)*hd0Range; % Initial plunge rate. [m/s]
	ad0 = (rand(1,1)*2-1)*ad0Range; % Initial pitch angle rate. [rad/s]

	% We run the simulation. We make the discrete-time prediction analytically, without using Simulink. This does the same as the linear Simulink simulation, but is of course much faster.
	applySettings; % We apply the settings which have been set so far, also taking into account any possible adjustments that have been made. This also sets up the initial conditions.
	Xm(:,2*experiment-1) = [x0';xd0']; % We store the initial state.
	Xm(:,2*experiment) = Ad*Xm(:,2*experiment-1); % We store the final state.
	rb(experiment) = -log(gamma)/(1 - gamma^T)*(Xm(:,2*experiment-1)'*Xb*Xm(:,2*experiment-1) - gamma^T*Xm(:,2*experiment)'*Xb*Xm(:,2*experiment)); % We calculate the weighted mean reward we accumulate during the experiment. We do this analytically.
end

% We walk through Xm to find the squared values of the state. We put this in Xms which stands for "Xm-squared".
Xms = zeros(10,2*nm);
for i = 1:nm
	Xms(:,i) = nonzeros(2*triu(Xm(:,i)*Xm(:,i)') - diag(Xm(:,i).^2)); % We take the diagonal elements squared and twice the non-diagonal upper triangular elements. This gives us x1^2, 2*x1*x2, x2^2, 2*x1*x3, 2*x2*x3, x3^2, and so on.
end

% Next we apply GP regression to the result. We set up the matrix M and the vector c.
MM = kron(eye(nm),[1,-gamma^T]); % We call this MM because the M matrix is already used as inertia matrix by the pitch-plunge system.
c = (1 - gamma^T)*rb;

% We also define the initial weight covariance and the noise covariance.
ranges = [h0Range;a0Range;hd0Range;ad0Range]; % We set up an array of length scales for the state parameters.
Kw = log(gamma)^2*diag(nonzeros(triu(1./(ranges*ranges'))).^2); % We use the scales to set up the initial covariance matrix for the weights w. Again, we only take the upper triangular elements (all only once).
Sc = 1e-8*eye(nm); % We define the noise Sigma_c.

% Now we apply the GP regression equations to calculate the weights.
Sw = inv(Xms*MM'/Sc*MM*Xms' + inv(Kw)); % This is the posterior distribution Sigma_w.
muw = (Xms*MM'/Sc*MM*Xms' + inv(Kw))\Xms*MM'/Sc*c; % This is the posterior distribution mu_w.
wReal = -log(gamma)*nonzeros(triu(Xb)); % This is the analytical value for w.

% We display some results.
disp(['We compare the estimated w with the real one after ',num2str(nm),' measurements. This is for the case without noise.']);
errorPercentage = (muw - wReal)./wReal*100;
stdPercentage = sqrt(diag(Sw))./abs(wReal)*100;
for i = 1:length(muw)
	disp(['For element ',num2str(i),' of w, the error is ',num2str(errorPercentage(i)),'% of ',num2str(wReal(i)),'. The STD is ',num2str(stdPercentage(i)),'%.']);
end

% Next, we start the process of plotting the results. We set up the grid we will make predictions on.
hMin = -h0Range;
hMax = h0Range;
aMin = -a0Range;
aMax = a0Range;
nsPerDimension = 21; % This is the number of trial points per dimension.
ns = nsPerDimension^2; % This is the total number of trial points.
[x1Mesh,x2Mesh] = meshgrid(linspace(hMin,hMax,nsPerDimension),linspace(aMin,aMax,nsPerDimension));
Xs = [reshape(x1Mesh,1,ns); reshape(x2Mesh,1,ns); zeros(2,ns)];

% We calculate the true value.
trueValue = -log(gamma)*diag(Xs'*Xb*Xs);
trueValue = reshape(trueValue, nsPerDimension, nsPerDimension);

% We set up the squared input vectors.
Xss = zeros(10,ns);
for i = 1:ns
	Xss(:,i) = nonzeros(2*triu(Xs(:,i)*Xs(:,i)') - diag(Xs(:,i).^2) + pi*triu(ones(4))) - pi; % We apply a trick here to make sure the nonzeros function works properly and doesn't cut out values which are supposed to be zero.
end

% We apply GP prediction using the weights.
mPost = muw'*Xss; % This is the posterior mean vector.
SPost = Xss'*Sw*Xss; % This is the posterior covariance matrix.
sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.

% % Alternatively to the above, we could have also used the general GP regression equations, which would have resulted in exactly the same thing, except we would not have an estimate of w.
% Kmm = Xms'*Kw*Xms;
% Kms = Xms'*Kw*Xss;
% Ksm = Kms';
% Kss = Xss'*Kw*Xss;
% mm = zeros(2*nm,1);
% ms = zeros(ns,1);
% mPost = ms + Ksm*MM'/(MM*Kmm*MM' + Sc)*(c - MM*mm); % This is the posterior mean vector.
% SPost = Kss - Ksm*MM'/(MM*Kmm*MM' + Sc)*MM*Kms; % This is the posterior covariance matrix.
% sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
% mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
% sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.

% And then we plot the result.
figure(1);
clf(1);
hold on;
grid on;
sDown = surface(x1Mesh, x2Mesh, mPost - 2*sPost);
set(sDown,'FaceAlpha',0.3);
set(sDown,'LineStyle','none');
sUp = surface(x1Mesh, x2Mesh, mPost + 2*sPost);
set(sUp,'FaceAlpha',0.3);
set(sUp,'LineStyle','none');
sMid = surface(x1Mesh, x2Mesh, mPost);
set(sMid,'FaceAlpha',0.8);
% sTrue = surface(x1Mesh, x2Mesh, trueValue);
% set(sTrue,'FaceAlpha',0.8);
if useColor == 0
	set(sDown,'FaceColor',[0.5,0.5,0.5]);
	set(sUp,'FaceColor',[0.5,0.5,0.5]);
	set(sMid,'FaceColor',[0.5,0.5,0.5]);
% 	set(sTrue,'FaceColor',[0.8,0.8,0.8]);
else
	set(sDown,'FaceColor',[0,0,1]);
	set(sUp,'FaceColor',[0,0,1]);
	set(sMid,'FaceColor',[0,0,1]);
% 	set(sTrue,'FaceColor',[0,1,0]);
end
xlabel('h_0');
ylabel('\alpha_0');
zlabel('V(x_0)');
view([-112,25]);

% We save the figure, if necessary.
if exportFigs ~= 0
	export_fig(['ValueFunctionSingleController.png'],'-transparent');
end

%% Here we start the second experiment. We run simulations subject to process noise and plot the resulting value function.

% We set some important settings.
sigmaAlpha2 = (a0Range/10)^2; % This is \sigma_\alpha^2, being the intensity of the noise we put on the angle of attack deviation.
W = At*[0;1;0;0]*sigmaAlpha2*[0,1,0,0]*At';

% We calculate discrete-time system matrices for the time step dt.
Ad = expm(At*dt); % This is the discrete-time A matrix.
XV = lyap(At,W);
XVdt = XV - expm(At*dt)*XV*expm(At'*dt); % We calculate X^V(dt) which also happens to be the discrete-time noise matrix.
if max(max(abs(XVdt))) > 0
	% We find the Cholesky decomposition of XVdt. To make sure Matlab can do this, we must use some kind of epsilon. We search for the smallest one.
	choleskyDecompositionWorked = 0;
	eps = 1e-20;
	while choleskyDecompositionWorked == 0
		try
			VdChol = chol(XVdt + eps); % This is the cholesky decomposition of X^V(dt), used to easily generate noise.
			choleskyDecompositionWorked = 1;
		catch
			eps = eps*10;
		end
	end
else
	VdChol = 0*XVdt; % If there is no noise, we use a zero Cholesky decomposition.
end

% We set up space for certain matrices.
xt = zeros(4,numDataPoints);
value = zeros(nm,1);

rng(2, 'twister'); % We fix Matlab's random number generator, so that it always creates the results shown in the thesis.
for experiment = 1:nm
	% We set the initial state for the simulation.
	h0 = (rand(1,1)*2-1)*h0Range; % Initial plunge. [m]
	a0 = (rand(1,1)*2-1)*a0Range; % Initial pitch angle. [rad]
	hd0 = (rand(1,1)*2-1)*hd0Range; % Initial plunge rate. [m/s]
	ad0 = (rand(1,1)*2-1)*ad0Range; % Initial pitch angle rate. [rad/s]

 	% We run the simulation.
	applySettings; % We apply the settings which have been set so far, also taking into account any possible adjustments that have been made. This also sets up the initial conditions.
	xt(:,1) = [h0;a0;hd0;ad0]; % We set up the initial state.
	value(experiment) = 0;
	for i = 2:numDataPoints
		xt(:,i) = Ad*xt(:,i-1) + VdChol'*randn(4,1); % We calculate the new state using the discrete-time system matrices.
		value(experiment) = value(experiment) - (gamma^t(i-1)*xt(:,i-1)'*Qt*xt(:,i-1) + gamma^t(i)*xt(:,i)'*Qt*xt(:,i))*dt/2; % We add this time step to the cost integrator.
	end
	
	% We make the discrete-time prediction analytically, without using Simulink. This does the same as the linear Simulink simulation, but is of course much faster.
	Xm(:,2*experiment-1) = xt(:,1); % We store the initial state.
	Xm(:,2*experiment) = xt(:,end); % We store the final state.
	rb(experiment) = -log(gamma)/(1 - gamma^T)*value(experiment);
end

% We walk through Xm to find the squared values of the state. We put this in Xms which stands for "Xm-squared". We also add a one to the end.
Xms = zeros(11,2*nm);
for i = 1:nm
	Xms(:,i) = [nonzeros(2*triu(Xm(:,i)*Xm(:,i)') - diag(Xm(:,i).^2));1]; % We take the diagonal elements squared and twice the non-diagonal upper triangular elements. This gives us x1^2, 2*x1*x2, x2^2, 2*x1*x3, 2*x2*x3, x3^2, and so on.
end

% We now add an extra term to Kw to take into account the bias. We also adjust the noise parameter, because now there actually is noise present. We will tune both parameters automatically.
sc = 1e-2; % This is an initial value to start the optimization process from.
kb = 1; % This is an initial value to start the optimization process from.
param = [sc;kb];
options = optimset('Display', 'off') ; % We do not want any output from fmincon.
param = fmincon(@(param)(nm/2*log(2*pi) + 1/2*logdet(MM*Xms'*diag([diag(Kw);param(2)^2])*Xms*MM' + param(1)^2*eye(nm)) + 1/2*c'/(MM*Xms'*diag([diag(Kw);param(2)^2])*Xms*MM' + param(1)^2*eye(nm))*c), param, -eye(2), zeros(2,1), [], [], [], [], [], options); % We minimize minus the log-likelihood, thus maximizing the log-likelihood. We also constrain the parameters to be positive.
sc = param(1);
% sc = 0.34; % We can also override this with a more physically correct variance level. (See the code at the end of this block.)
Sc = sc^2*eye(nm);
kb = param(2);
Kw(11,11) = kb^2;

% Now we apply the GP regression equations to calculate the weights.
c = (1 - gamma^T)*rb;
Sw = inv(Xms*MM'/Sc*MM*Xms' + inv(Kw)); % This is the posterior distribution Sigma_w.
muw = (Xms*MM'/Sc*MM*Xms' + inv(Kw))\Xms*MM'/Sc*c; % This is the posterior distribution mu_w.
wReal = [-log(gamma)*nonzeros(triu(Xb));trace(W*Xb)]; % This is the analytical value for w.

% We display some results.
disp(['We compare the estimated w with the real one after ',num2str(nm),' measurements. This is for the case with process noise and manually chosen hyperparameters.']);
errorPercentage = (muw - wReal)./wReal*100;
stdPercentage = sqrt(diag(Sw))./abs(wReal)*100;
for i = 1:length(muw)
	disp(['For element ',num2str(i),' of w, the error is ',num2str(errorPercentage(i)),'% of ',num2str(wReal(i)),'. The STD is ',num2str(stdPercentage(i)),'%.']);
end

% Next, we start the process of plotting the results. We adjust the set of squared input vectors.
Xss(11,:) = ones(1,ns);
trueValueWithNoise = trueValue + trace(W*Xb);

% We apply GP prediction using the weights.
mPost = muw'*Xss; % This is the posterior mean vector.
SPost = Xss'*Sw*Xss; % This is the posterior covariance matrix.
sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.

% And then we plot the result.
figure(2);
clf(2);
hold on;
grid on;
sDown = surface(x1Mesh, x2Mesh, mPost - 2*sPost);
set(sDown,'FaceAlpha',0.3);
set(sDown,'LineStyle','none');
sUp = surface(x1Mesh, x2Mesh, mPost + 2*sPost);
set(sUp,'FaceAlpha',0.3);
set(sUp,'LineStyle','none');
sMid = surface(x1Mesh, x2Mesh, mPost);
set(sMid,'FaceAlpha',0.8);
sTrue = surface(x1Mesh, x2Mesh, trueValueWithNoise);
set(sTrue,'FaceAlpha',0.8);
if useColor == 0
	set(sDown,'FaceColor',[0.5,0.5,0.5]);
	set(sUp,'FaceColor',[0.5,0.5,0.5]);
	set(sMid,'FaceColor',[0.5,0.5,0.5]);
	set(sTrue,'FaceColor',[0.8,0.8,0.8]);
else
	set(sDown,'FaceColor',[0,0,1]);
	set(sUp,'FaceColor',[0,0,1]);
	set(sMid,'FaceColor',[0,0,1]);
	set(sTrue,'FaceColor',[0,1,0]);
end
xlabel('h_0');
ylabel('\alpha_0');
zlabel('V(x_0)');
view([-146,14]);
axis([-h0Range,h0Range,-a0Range,a0Range,-3,0.5]);

% We save the figure, if necessary.
if exportFigs ~= 0
	export_fig(['ValueFunctionSingleControllerWithNoise.png'],'-transparent');
end

% We also look at what a reasonable value of sigma_c^2 would have been, from a physical point of view. For this, we calculate the noise variance V[J_T] for all initial states in Xm that we used.
% We use the theory from Appendix C.4 from the thesis for this.
EJ = zeros(nm,1);
VJ = zeros(nm,1);
EJT = zeros(nm,1);
VJT = zeros(nm,1);
for i = 1:nm,
	% We extract the initial state.
	mu0 = Xm(:,2*i-1); % \mu_0
	Psi0 = mu0*mu0'; % \Psi_0

	% We calculate Lyapunov matrices and other important matrices to calculate the cost.
	Delta = Psi0 - XV; % \Delta
	PsiT = expm(At*T)*(Psi0 - XV)*expm(At'*T) + XV; % \Psi(T)
	Aa = At + a*I; % A_\alpha
	A2a = At + 2*a*I; % A_{2\alpha}
	Ama = At - a*I; % A_{-\alpha}
	XbaQ = lyap(Aa',Qt); % \bar{X}_\alpha^Q
	XbaQT = XbaQ - expm(Aa'*T)*XbaQ*expm(Aa*T); % \bar{X}_\alpha^Q(T)
	XbmaQ = lyap(Ama',Qt); % \bar{X}_{-\alpha}^Q
	XbmaQT = XbmaQ - expm(Ama'*T)*XbmaQ*expm(Ama*T); % \bar{X}_{-\alpha}^Q(T)
	X2aD = lyap(A2a,Delta); % X_{2\alpha}^\Delta
	X2atT = [I,Z]*expm([A2a,X2aD*expm(A2a'*T)*Qt;Z,At]*T)*[Z;I];
	X2aPsi0 = lyap((At+2*a*I),Psi0);
	X2aV = lyap((At+2*a*I),W);

	% We calculate the mean and variance for the current alpha, both in the infinite-time and the finite-time case.
	EJ(i) = log(gamma)*trace((Psi0 - W/(2*a))*XbaQ);
	VJ(i) = log(gamma)^2*(2*trace((Psi0*XbaQ)^2) - 2*(mu0'*XbaQ*mu0)^2 + 4*trace((X2aPsi0 - X2aV/(4*a))*XbaQ*W*XbaQ));
	EJT(i) = log(gamma)*trace((Psi0 - exp(2*a*T)*PsiT + (1 - exp(2*a*T))*(-W/(2*a)))*XbaQ);
	VJT(i) = log(gamma)^2*(2*trace((Delta*XbaQT)^2) - 2*(mu0'*XbaQT*mu0)^2 + 4*trace(XV*Qt*(XV*(exp(4*a*T)*XbmaQT - XbaQT)/(4*a) + 2*X2aD*XbaQT - 2*X2atT)));
end
disp(['The physically correct value of sigma_c would be ',num2str(sqrt(mean(VJT))),'.']);

%% We will use the same data, but now apply hyperparameter tuning to all parameters of Kw.

% We investigate the log-likelihood of the hyperparameters so far.
logp = -nm/2*log(2*pi) - 1/2*logdet(MM*Xms'*Kw*Xms*MM' + Sc) - 1/2*c'/(MM*Xms'*Kw*Xms*MM' + Sc)*c;
disp(['We have tuned sigma_c to ',num2str(sc),'.']);
disp(['This gave a log-likelihood of ',num2str(logp),'.']);

% Next, we use the log-likelihood to tune all parameters. To do this, we give fmincon a normalized vector, because it cannot deal very well with parameters largely varying in magnitude.
param0 = [diag(Kw);sc];
paramNorm = fmincon(@(paramNorm)(nm/2*log(2*pi) + 1/2*logdet(MM*Xms'*diag(paramNorm(1:11).*param0(1:11))*Xms*MM' + (paramNorm(12)*param0(12))^2*eye(nm)) + 1/2*c'/(MM*Xms'*diag(paramNorm(1:11).*param0(1:11))*Xms*MM' + (paramNorm(12)*param0(12))^2*eye(nm))*c), ones(12,1), -eye(12), zeros(12,1), [], [], [], [], [], options); % We optimize sigma_c. We also constrain it to be positive.
param = paramNorm.*param0;
Kw = diag(param(1:11));
sc = param(12);
Sc = sc^2*eye(nm);
logp = -nm/2*log(2*pi) - 1/2*logdet(MM*Xms'*Kw*Xms*MM' + Sc) - 1/2*c'/(MM*Xms'*Kw*Xms*MM' + Sc)*c;
disp(['We have tuned sigma_c to ',num2str(sc),'.']);
disp(['The log-likelihood for the tuned hyperparameters is ',num2str(logp),'.']);

% We now will do the regression again.
Sw = inv(Xms*MM'/Sc*MM*Xms' + inv(Kw)); % This is the posterior distribution Sigma_w.
muw = (Xms*MM'/Sc*MM*Xms' + inv(Kw))\Xms*MM'/Sc*c; % This is the posterior distribution mu_w.

% We display some results.
disp(['We compare the estimated w with the real one after ',num2str(nm),' measurements. This is for the tuned hyperparameters.']);
errorPercentage = (muw - wReal)./wReal*100;
stdPercentage = sqrt(diag(Sw))./abs(wReal)*100;
for i = 1:length(muw)
	disp(['For element ',num2str(i),' of w, the error is ',num2str(errorPercentage(i)),'% of ',num2str(wReal(i)),'. The STD is ',num2str(stdPercentage(i)),'%.']);
end

% And we start setting up the plot again. Here we calculate the trial mean and covariance.
mPost = muw'*Xss; % This is the posterior mean vector.
SPost = Xss'*Sw*Xss; % This is the posterior covariance matrix.
sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.

% And then we plot the result.
figure(3);
clf(3);
hold on;
grid on;
sDown = surface(x1Mesh, x2Mesh, mPost - 2*sPost);
set(sDown,'FaceAlpha',0.3);
set(sDown,'LineStyle','none');
sUp = surface(x1Mesh, x2Mesh, mPost + 2*sPost);
set(sUp,'FaceAlpha',0.3);
set(sUp,'LineStyle','none');
sMid = surface(x1Mesh, x2Mesh, mPost);
set(sMid,'FaceAlpha',0.8);
sTrue = surface(x1Mesh, x2Mesh, trueValueWithNoise);
set(sTrue,'FaceAlpha',0.8);
if useColor == 0
	set(sDown,'FaceColor',[0.5,0.5,0.5]);
	set(sUp,'FaceColor',[0.5,0.5,0.5]);
	set(sMid,'FaceColor',[0.5,0.5,0.5]);
	set(sTrue,'FaceColor',[0.8,0.8,0.8]);
else
	set(sDown,'FaceColor',[0,0,1]);
	set(sUp,'FaceColor',[0,0,1]);
	set(sMid,'FaceColor',[0,0,1]);
	set(sTrue,'FaceColor',[0,1,0]);
end
xlabel('h_0');
ylabel('\alpha_0');
zlabel('V(x_0)');
view([-146,14]);
axis([-h0Range,h0Range,-a0Range,a0Range,-3,0.5]);

% We save the figure, if necessary.
if exportFigs ~= 0
	export_fig(['ValueFunctionSingleControllerWithNoiseTunedHyperparameters.png'],'-transparent');
end

%% Next, we start varying the controllers too. We then look at how well each controller performs.

% We start by setting up some settings.
nm = 500; % We will use a few more measurements, because this problem has more dimensions and hence requires more data.
W = 0*W; % We will deactive the noise, to make sure we get decent results. Otherwise we need even more measurements, making the algorithm very slow.
Psi0 = (1/2)^2*(ranges*ranges'); % We define the distribution of the initial state which we want to optimize the controllers over.
MM = kron(eye(nm),[1,-gamma^T]); % Because we have changed nm, we should also make the M matrix bigger.

% We now calculate the optimal controller gains.
X = are(sysA + a*I, sysB/R*sysB', Q);
sysF = R\sysB'*X;
gainValue = trace((W - 2*a*Psi0)*lyap((sysA + a*I - sysB*sysF)', -(Q + sysF'*R*sysF)));
disp(['The optimal control gains are [',num2str(sysF(1)),', ',num2str(sysF(2)),', ',num2str(sysF(3)),', ',num2str(sysF(4)),']. The value is ',num2str(gainValue),'.']);

% We will only use the first two gains in our experiments. So we optimize them separately.
gains = sysF(1:2)';
gains = fmincon(@(gains)(-trace((0*W - 2*a*Psi0)*lyap((sysA + a*I - sysB*[gains',0,0])', -(Q + [gains',0,0]'*R*[gains',0,0])))), gains, [], [], [], [], [], [], [], options); % We minimize minus the value function, thus maximizing the value or minimizing the cost.
gainValue = trace((W - 2*a*Psi0)*lyap((sysA + a*I - sysB*[gains',0,0])', -(Q + [gains',0,0]'*R*[gains',0,0])));
disp(['When using only the first two gains, the optimal gains are [',num2str(gains(1)),', ',num2str(gains(2)),']. The value is ',num2str(gainValue),'.']);

% We define which controllers we will try.
sysFMin = [-40,0,0,0]; % This is the minimum for the controller gain matrix \tilde{F}.
sysFMax = [0,2.5,0,0]; % This is the maximum for the controller gain matrix \tilde{F}.

% We set up/adjust storage matrices.
Xm = zeros(8,2*nm); % This set will contain all input data.
value = zeros(nm,1); % This array will contain the values we accumulate during the experiments.
rb = zeros(nm,1); % This is the vector \bar{r}.

% We start iterating, each time choosing a controller and evaluating the system.
rng(1, 'twister'); % We fix Matlab's random number generator, so that it always creates the results shown in the thesis.
useSimulink = 0; % Do we use Simulink? Or do we use the analytical linear system expressions?
useNonlinear = 1; % We indicate we want the nonlinear Simulink model. (Otherwise it's just the same as not using Simulink at all.)
for experiment = 1:nm
	% We pick a controller and implement it in the system.
	sysF = sysFMin + rand(1,4).*(sysFMax - sysFMin);
	At = sysA - sysB*sysF; % This is the matrix \tilde{A} = A - B*F.
	Qt = Q + sysF'*R*sysF; % This is the matrix \tilde{Q} = Q + F^T*R*F.
	Xb = lyap((At+a*eye(4))', -Qt); % This is the matrix Xb which we eventually want to approximate. We add the minus sign here because we use negative rewards. As a result, the value will be negative.

	% We calculate discrete-time system matrices for the time step dt.
	Ad = expm(At*dt); % This is the discrete-time A matrix.
	XV = lyap(At,W);
	XVdt = XV - expm(At*dt)*XV*expm(At'*dt); % We calculate X^V(dt) which also happens to be the discrete-time noise matrix.
	if max(max(abs(XVdt))) > 0
		% We find the Cholesky decomposition of XVdt. To make sure Matlab can do this, we must use some kind of epsilon. We search for the smallest one.
		choleskyDecompositionWorked = 0;
		eps = 1e-20;
		while choleskyDecompositionWorked == 0
			try
				VdChol = chol(XVdt + eps); % This is the cholesky decomposition of X^V(dt), used to easily generate noise.
				choleskyDecompositionWorked = 1;
			catch
				eps = eps*10;
			end
		end
	else
		VdChol = 0*XVdt; % If there is no noise, we use a zero Cholesky decomposition.
	end

	% We set the initial state for the simulation.
	h0 = (rand(1,1)*2-1)*h0Range; % Initial plunge. [m]
	a0 = (rand(1,1)*2-1)*a0Range; % Initial pitch angle. [rad]
	hd0 = (rand(1,1)*2-1)*hd0Range; % Initial plunge rate. [m/s]
	ad0 = (rand(1,1)*2-1)*ad0Range; % Initial pitch angle rate. [rad/s]

 	% We run the simulation.
	applySettings; % We apply the settings which have been set so far, also taking into account any possible adjustments that have been made. This also sets up the initial conditions.
	if useSimulink == 1
		disp(['Starting up Simulink experiment ',num2str(experiment),' out of ',num2str(nm),'.']);
		t = sim('../PitchPlunge/PitchPlunge');
		Xm(:,2*experiment-1) = [x(1,:)';xd(1,:)';sysF'];
		Xm(:,2*experiment) = [x(end,:)';xd(end,:)';sysF'];
		rb(experiment) = accReward(end)/accWeight(end);
	else
		xt(:,1) = [h0;a0;hd0;ad0]; % We set up the initial state.
		value(experiment) = 0;
		for i = 2:numDataPoints
			xt(:,i) = Ad*xt(:,i-1) + VdChol'*randn(4,1); % We calculate the new state using the discrete-time system matrices.
			value(experiment) = value(experiment) - (gamma^t(i-1)*xt(:,i-1)'*Qt*xt(:,i-1) + gamma^t(i)*xt(:,i)'*Qt*xt(:,i))*dt/2; % We add this time step to the cost integrator.
		end
		Xm(:,2*experiment-1) = [xt(:,1);sysF']; % We store the initial state and the controller settings used.
		Xm(:,2*experiment) = [xt(:,end);sysF']; % We store the final state and the controller settings used.
		rb(experiment) = -log(gamma)/(1 - gamma^T)*value(experiment);
	end
end
c = (1 - gamma^T)*rb;

% Next, we start to set up the GP regression algorithm. 
%% We set up the Xm-squared matrix again.
Xms = zeros(11,2*nm);
for i = 1:nm
	Xms(:,i) = [nonzeros(2*triu(Xm(1:4,i)*Xm(1:4,i)') - diag(Xm(1:4,i).^2));1]; % We take the diagonal elements squared and twice the non-diagonal upper triangular elements. This gives us x1^2, 2*x1*x2, x2^2, 2*x1*x3, 2*x2*x3, x3^2, and so on.
end

% We set up Xs and Xss. Here, we vary the controller gains C_h and C_\alpha, keeping the rest at zero.
nsPerDimension = 21; % This is the number of trial points per dimension.
ns = nsPerDimension^2; % This is the total number of trial points.
[x1Mesh,x2Mesh] = meshgrid(linspace(sysFMin(1),sysFMax(1),nsPerDimension),linspace(sysFMin(2),sysFMax(2),nsPerDimension));
Xs = [zeros(4,ns); reshape(x1Mesh,1,ns); reshape(x2Mesh,1,ns); zeros(2,ns)]; % We also set values for the initial state here (we set it to zero) but we won't use that anyway.
Xss = repmat([nonzeros(2*triu(Psi0) - diag(diag(Psi0)) + pi*triu(ones(4))) - pi;1],1,ns);

% We calculate analytically what our outcome should be. So the expected value from the Psi0 state distribution with the given noise.
trueValue = zeros(ns,1);
for i = 1:ns
	sysF = Xs(5:8,i)';
	At = sysA - sysB*sysF;
	Qt = Q + sysF'*R*sysF;
	Xb = lyap((At+a*eye(4))', -Qt);
	trueValue(i) = trace((W - 2*a*Psi0)*Xb);
end
trueValue = reshape(trueValue, nsPerDimension, nsPerDimension); % We put the result in a square format again.

% We set up the hyperparameters.
Kw = log(gamma)^2*diag(nonzeros(triu(1./(ranges*ranges'))).^2); % We redefine Kw, because it has been changed by earlier blocks.
kb = 1; % I'm a bit lazy here. I just manually define the gain variance instead of tuning it.
Kw(11,11) = kb^2;
CRange = (1/4)*betaRange./[h0Range,a0Range,hd0Range,ad0Range]; % This is the length scale for the controller parameters. We could set up Lambda = diag(CRange.^2), but we don't really need that.

% We now choose whether we either tune the hyperparameter or manually select it ourselves. You can comment or uncomment the second line to turn off/on the tuning of sigma_c. Turning it off will
% give you Figure 3.14 (left) while turning it on will give you Figure 3.14 (right) from the thesis.
sc = 1e-4; % This is the manual choice.
% sc = fmincon(@(sc)(nm/2*log(2*pi) + 1/2*logdet(MM*((Xms'*Kw*Xms).*exp(-1/2*sum((repmat(permute(Xm(5:8,:),[3,2,1]),2*nm,1) - repmat(permute(Xm(5:8,:),[2,3,1]),1,2*nm)).^2./repmat(permute(CRange.^2,[3,1,2]),2*nm,2*nm), 3)))*MM' + sc^2*eye(nm)) + 1/2*c'/(MM*((Xms'*Kw*Xms).*exp(-1/2*sum((repmat(permute(Xm(5:8,:),[3,2,1]),2*nm,1) - repmat(permute(Xm(5:8,:),[2,3,1]),1,2*nm)).^2./repmat(permute(CRange.^2,[3,1,2]),2*nm,2*nm), 3)))*MM' + sc^2*eye(nm))*c), sc, -eye(1), zeros(1,1), [], [], [], [], [], options); % We optimize both the length parameters of the controllers (out of which the last two are actually useless) and we optimize sigma_c. Sorry about the overly long line. There was no way of getting around this without making a separate function in a separate file, which would have been even more confusing. Ah, the horror called Matlab scripts...
disp(['The value of sc used is ',num2str(sc),'.']);
Sc = sc^2*eye(nm);

% We set up the squared exponential part for the controller.
X = [Xm(5:8,:),Xs(5:8,:)];
n = size(X,2);
diff = repmat(permute(X,[3,2,1]),n,1) - repmat(permute(X,[2,3,1]),1,n); % This is matrix containing differences between input points. We have rearranged things so that indices 1 and 2 represent the numbers of vectors, while index 3 represents the element within the vector.
corr = exp(-1/2*sum(diff.^2./repmat(permute(CRange.^2,[3,1,2]),n,n), 3)); % This is the correlation matrix. It contains the correlations of each combination of c.
corrmm = corr(1:2*nm,1:2*nm);
corrms = corr(1:2*nm,2*nm+1:end);
corrsm = corrms';
corrss = corr(2*nm+1:end,2*nm+1:end);

% Next, we want to do the exact same thing but then not by calculating the distribution of the weights w, but by directly defining a covariance function.
Kmm = (Xms'*Kw*Xms).*corrmm;
Kms = (Xms'*Kw*Xss).*corrms;
Ksm = Kms';
Kss = (Xss'*Kw*Xss).*corrss;
mm = zeros(2*nm,1);
ms = zeros(ns,1);
mPost = ms + Ksm*MM'/(MM*Kmm*MM' + Sc)*(c - MM*mm); % This is the posterior mean vector.
SPost = Kss - Ksm*MM'/(MM*Kmm*MM' + Sc)*MM*Kms; % This is the posterior covariance matrix.
sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.

% And then we plot the result.
figure(4);
clf(4);
hold on;
grid on;
sDown = surface(x1Mesh, x2Mesh, mPost - 2*sPost);
set(sDown,'FaceAlpha',0.3);
set(sDown,'LineStyle','none');
sUp = surface(x1Mesh, x2Mesh, mPost + 2*sPost);
set(sUp,'FaceAlpha',0.3);
set(sUp,'LineStyle','none');
sMid = surface(x1Mesh, x2Mesh, mPost);
set(sMid,'FaceAlpha',0.8);
sTrue = surface(x1Mesh, x2Mesh, trueValue);
set(sTrue,'FaceAlpha',0.8);
if useColor == 0
	set(sDown,'FaceColor',[0.5,0.5,0.5]);
	set(sUp,'FaceColor',[0.5,0.5,0.5]);
	set(sMid,'FaceColor',[0.5,0.5,0.5]);
	set(sTrue,'FaceColor',[0.8,0.8,0.8]);
else
	set(sDown,'FaceColor',[0,0,1]);
	set(sUp,'FaceColor',[0,0,1]);
	set(sMid,'FaceColor',[0,0,1]);
	set(sTrue,'FaceColor',[0,1,0]);
end
xlabel('C_h');
ylabel('C_\alpha');
zlabel('V(x_0,\theta)');
view([116,12]);

% We save the figure, if necessary.
if exportFigs ~= 0
	export_fig(['ValueFunctionForVaryingController.png'],'-transparent');
end

% Finally we optimize the prediction mean with respect to the gains to find the optimal predicted gain.
gains = [-20;2]; % We initialize the gains which we will optimize at some random incorrect place. This is then fed to the fmincon function.
[gains,gainValue] = fmincon(@(gains)(-(([nonzeros(2*triu(Psi0) - diag(diag(Psi0)) + pi*triu(ones(4))) - pi;1]'*Kw*Xms).*exp(-1/2*sum((repmat(permute([gains;0;0],[3,2,1]),1,2*nm) - repmat(permute(Xm(5:8,:),[3,2,1]),1,1)).^2./repmat(permute(CRange.^2,[3,1,2]),1,2*nm), 3)))*MM'/(MM*Kmm*MM' + Sc)*c), gains, [eye(2);-eye(2)], [sysFMax(1:2)';-sysFMin(1:2)'], [], [], [], [], [], options); % We maximize the approximated cost (minimize minus the cost) with respect to the controller gains. We also constrain the gains to the plotted area.
disp(['The optimal controller gains predicted by the GP algorithm are [',num2str(gains(1)),', ',num2str(gains(2)),']. The value is ',num2str(-gainValue),'.']);
