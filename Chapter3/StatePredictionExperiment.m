% In this file we apply linear covariance functions, trying to approximate the linearized dynamics of a simple pitch-plunge system.
% To use it, make sure that the Matlab directory is set to the directory of this file. Then you can run this file.

% We set up the workspace, ready for executing scripts.
clear all; % Empty the workspace.
clc; % Empty the command window.
exportFigs = 0; % Do we export figures? 0 for no, 1 (or anything else) for yes.
useColor = 1; % Should we set up plots for colored output (1) or black-and-white output (0)?

% We add paths containing files which we will need.
addpath('../PitchPlunge/Definitions/');
addpath('../PitchPlunge/Controllers/');
addpath('../ExportFig/');
addpath('../Tools/');

% We define colors.
black = [0 0 0];
white = [1 1 1];
if useColor == 0
	red = [0 0 0];
	green = [0.6 0.6 0.6];
	blue = [0.2 0.2 0.2];
	yellow = [0.4 0.4 0.4];
	grey = [0.8 0.8 0.8];
else
	red = [0.8 0 0];
	green = [0 0.4 0];
	blue = [0 0 0.8];
	yellow = [0.6 0.6 0];
	grey = [0.8 0.8 1];
end

% Next, it's time to gather data for GP regression. We set the number of measurements that we want to do.
nm = 30; % We set the number of time steps we want to feed to the GP.
Xm = zeros(5,nm); % This set will contain all input data.
fmh = zeros(nm,4); % This set will contain all output data.
fmhLinear = fmh; % We add an extra storage for the linear system outcomes.

% To start off, we define timing data.
dt = 0.001; % We define the simulation time step.
T = 0.1; % We define the simulation length.
numDataPoints = ceil(T/dt)+1; % We calculate the number of data points we'll be having.

% We also set up other parameters. These are set to default values.
defineFlow; % We set up the flow properties.
defineStructuralParameters; % We define the structural parameters.
defineInitialConditions; % We define the initial conditions.
defineControllerParameters; % We set up the controller parameters.

% We define the range for the initial state and the control input.
U0 = 15; % We adjust the wind speed from its default value.
h0Range = 5e-3;
a0Range = 6e-2;
hd0Range = 5e-2;
ad0Range = 1e0;
betaRange = 5e-1;
useNonlinear = 1; % We indicate whether we use the linear or the nonlinear model.

% We define which controller we will use.
controller = @constantController;
global constantControllerValue;

% We set up the discrete-time matrices for the linearized pitch-plunge system. These can be used so we don't have to run the Simulink simulation for the linear model, which saves us time.
applySettings; % We apply the settings which have been set so far, also taking into account any possible adjustments that have been made. This also defines system matrices.
At = [zeros(2,2), eye(2); -M\(K+U0^2*D), -M\(C+U0*E)];
Bt = [zeros(2,1); M\(U0^2*F)];
Ae = expm(At*T);
SystemMatrix = [Ae,(Ae - eye(4))/At*Bt];

% We now loop through the experiments to obtain data.
rng(1, 'twister'); % We fix Matlab's random number generator, so that it always creates functions which I've found to be pretty representative as far as random samples go.
for experiment = 1:nm
	% We set the initial state for the simulation.
	h0 = (rand(1,1)*2-1)*h0Range; % Initial plunge. [m]
	a0 = (rand(1,1)*2-1)*a0Range; % Initial pitch angle. [rad]
	hd0 = (rand(1,1)*2-1)*hd0Range; % Initial plunge rate. [m/s]
	ad0 = (rand(1,1)*2-1)*ad0Range; % Initial pitch angle rate. [rad/s]
	constantControllerValue = (rand(1,1)*2-1)*betaRange; % Control input. [rad]

	% We run the simulation.
	applySettings; % We apply the settings which have been set so far, also taking into account any possible adjustments that have been made. This also sets up the initial conditions.
	t = sim('../PitchPlunge/PitchPlunge');
	Xm(:,experiment) = [x(1,:)';xd(1,:)';constantControllerValue];
	fmh(experiment,:) = [x(end,:),xd(end,:)];
	
	% We make the discrete-time prediction without using Simulink. This does the same as the linear Simulink simulation, but is of course much faster.
	Xm(:,experiment) = [x0';xd0';constantControllerValue];
	fmhLinear(experiment,:) = (SystemMatrix*Xm(:,experiment))';
end

% We set up scaling parameters. These are pretty much the maximum values of the parameters that ever occur. We will use them to define the prior of the weights matrix.
xScale = [1e-2;2e-1;1e-1;5e0;5e-1];
Kw = 4*repmat(diag(1./xScale.^2),[1,1,4]).*repmat(permute(xScale(1:4).^2,[2,3,1]),[5,5,1]); % These are the priors of the weight matrices. For the diagonal elements, they are the output scale squared divided by the input scale squared.

% We set up the grid we will make predictions on.
hMin = -h0Range;
hMax = h0Range;
aMin = -a0Range;
aMax = a0Range;
nsPerDimension = 21; % This is the number of trial points per dimension.
ns = nsPerDimension^2; % This is the total number of trial points.
[x1Mesh,x2Mesh] = meshgrid(linspace(hMin,hMax,nsPerDimension),linspace(aMin,aMax,nsPerDimension));
Xs = [reshape(x1Mesh,1,ns); reshape(x2Mesh,1,ns); zeros(3,ns)];

% We calculate the posterior (discrete) system matrix, based on the data that we have measured. We first do this for the linear data.
SystemMatrixPredicted = zeros(4,5);
SystemMatrixSTD = zeros(4,5);
SystemMatrixCovariance = zeros(5,5,4);
for i = 1:4
	sfm = xScale(i)/100; % We set the noise level based on the length scale.
	Sfm = sfm^2*eye(nm); % We set up the noise matrix.
	muw = (Xm/Sfm*Xm' + inv(Kw(:,:,i)))\Xm/Sfm*fmhLinear(:,i); % This is the posterior mean of the weights.
	Sw = inv(Xm/Sfm*Xm' + inv(Kw(:,:,i))); % This is the posterior covariance matrix of the weights.
	SystemMatrixPredicted(i,:) = muw';
	SystemMatrixSTD(i,:) = diag(Sw)';
	SystemMatrixCovariance(:,:,i) = Sw;
end

% We start making predictions for the plots. We do this for different outputs.
for outputIndex = 1:2
	fs = SystemMatrix*Xs;
	mPost = SystemMatrixPredicted(outputIndex,:)*Xs; % This is the posterior mean vector.
	SPost = Xs'*SystemMatrixCovariance(:,:,outputIndex)*Xs; % This is the posterior covariance matrix.
	sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
	mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
	sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.

	% And then we plot the result.
	figure(outputIndex);
	clf(outputIndex);
	hold on;
	grid on;
	sDown = surface(x1Mesh, x2Mesh, mPost - 2*sPost);
	set(sDown,'FaceAlpha',0.3);
	set(sDown,'LineStyle','none');
	set(sDown,'FaceColor',blue);
	sUp = surface(x1Mesh, x2Mesh, mPost + 2*sPost);
	set(sUp,'FaceAlpha',0.3);
	set(sUp,'LineStyle','none');
	set(sUp,'FaceColor',blue);
	sMid = surface(x1Mesh, x2Mesh, mPost);
	set(sMid,'FaceAlpha',0.8);
	set(sMid,'FaceColor',blue);
	xlabel('h_k');
	ylabel('\alpha_k');
	if outputIndex == 1
		zlabel('h_{k+1}');
	else
		zlabel('\alpha_{k+1}');
	end
	if outputIndex == 1
		view([-110,30])
	end
	if outputIndex == 2
		view([-110,30])
		axis([-h0Range,h0Range,-a0Range,a0Range,-0.1,0.1]);
	end

	% We also plot the result from the previous chapter.
	load('../Chapter2/CH2Predictions');
	sPrevious = surface(x1Mesh, x2Mesh, mPostStorage(:,:,outputIndex));
	set(sPrevious,'FaceAlpha',0.5);
	set(sPrevious,'FaceColor',green);
	if exportFigs ~= 0
		export_fig(['NextStatePredictionLinear',num2str(outputIndex),'.png'],'-transparent');
	end
end

% Next we do the same for the nonlinear data. We first predict the system matrix again.
SystemMatrixPredicted = zeros(4,5);
SystemMatrixSTD = zeros(4,5);
SystemMatrixCovariance = zeros(5,5,4);
for i = 1:4
	sfm = xScale(i)/100; % We set the noise level based on the length scale.
	Sfm = sfm^2*eye(nm); % We set up the noise matrix.
	muw = (Xm/Sfm*Xm' + inv(Kw(:,:,i)))\Xm/Sfm*fmh(:,i); % This is the posterior mean of the weights.
	Sw = inv(Xm/Sfm*Xm' + inv(Kw(:,:,i))); % This is the posterior covariance matrix of the weights.
	SystemMatrixPredicted(i,:) = muw';
	SystemMatrixSTD(i,:) = diag(Sw)';
	SystemMatrixCovariance(:,:,i) = Sw;
end

% We start making predictions for the plots. We do this for different outputs.
for outputIndex = 1:2
	fs = SystemMatrix*Xs;
	mPost = SystemMatrixPredicted(outputIndex,:)*Xs; % This is the posterior mean vector.
	SPost = Xs'*SystemMatrixCovariance(:,:,outputIndex)*Xs; % This is the posterior covariance matrix.
	sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
	mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
	sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.

	% And then we plot the result.
	figure(2+outputIndex);
	clf(2+outputIndex);
	hold on;
	grid on;
	sDown = surface(x1Mesh, x2Mesh, mPost - 2*sPost);
	set(sDown,'FaceAlpha',0.3);
	set(sDown,'LineStyle','none');
	set(sDown,'FaceColor',blue);
	sUp = surface(x1Mesh, x2Mesh, mPost + 2*sPost);
	set(sUp,'FaceAlpha',0.3);
	set(sUp,'LineStyle','none');
	set(sUp,'FaceColor',blue);
	sMid = surface(x1Mesh, x2Mesh, mPost);
	set(sMid,'FaceAlpha',0.8);
	set(sMid,'FaceColor',blue);
	xlabel('h_k');
	ylabel('\alpha_k');
	if outputIndex == 1
		zlabel('h_{k+1}');
	else
		zlabel('\alpha_{k+1}');
	end
	if outputIndex == 1
		view([-110,30])
	end
	if outputIndex == 2
		view([-110,30])
	end

	% We also plot the result from the previous chapter.
	load('../Chapter2/CH2Predictions');
	sPrevious = surface(x1Mesh, x2Mesh, mPostStorage(:,:,outputIndex));
	set(sPrevious,'FaceAlpha',0.5);
	set(sPrevious,'FaceColor',green);
	if exportFigs ~= 0
		export_fig(['NextStatePredictionNonlinear',num2str(outputIndex),'.png'],'-transparent');
	end
end

% Next, we will add an SE covariance function and see what effect this has. We choose the hyperparameters of the SE part of the covariance function. We do this for all the different outputs.
sfm = xScale(1:4)'/100;
lf = xScale(1:4)*4;
lx = [xScale,xScale];
mb = zeros(4,1);

% We set up the difference matrix, preparing ourselves for GP regression.
X = [Xm,Xs]; % We merge the measurement and trial points.
n = size(X,2); % This is the number of points.
diff = repmat(permute(X,[2,3,1]),[1,n]) - repmat(permute(X,[3,2,1]),[n,1]); % This is matrix containing differences between input points.

% We apply GP regression for each individual output.
for outputIndex = 1:2
 	K = X'*Kw(:,:,outputIndex)*X + lf(outputIndex)^2*exp(-1/2*sum(diff.^2./repmat(permute(lx(:,outputIndex).^2,[2,3,1]),[n,n,1]),3)); % This is the covariance matrix. It is the sum of the linear covariance function and the SE covariance function.
	Kmm = K(1:nm,1:nm);
	Kms = K(1:nm,nm+1:end);
	Ksm = Kms';
	Kss = K(nm+1:end,nm+1:end);
	Sfm = sfm(outputIndex)^2*eye(nm); % This is the noise covariance matrix.
	mm = mb(outputIndex)*ones(nm,1); % This is the mean vector m(Xm). We assume a constant mean function.
	ms = mb(outputIndex)*ones(ns,1); % This is the mean vector m(Xs). We assume a constant mean function.
	mPost = ms + Ksm/(Kmm + Sfm)*(fmh(:,outputIndex) - mm); % This is the posterior mean vector.
	SPost = Kss - Ksm/(Kmm + Sfm)*Kms; % This is the posterior covariance matrix.
	sPost = sqrt(diag(SPost)); % These are the posterior standard deviations.
	mPost = reshape(mPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
	sPost = reshape(sPost, nsPerDimension, nsPerDimension); % We put the result in a square format again.
	logp = -nm/2*log(2*pi) - 1/2*logdet(Kmm + Sfm) - 1/2*(fmh(:,outputIndex) - mm)'/(Kmm + Sfm)*(fmh(:,outputIndex) - mm); % In case we are interested, we can also calculate the log(p) value.
	
	% And then we plot the result.
	figure(4+outputIndex);
	clf(4+outputIndex);
	hold on;
	grid on;
	sDown = surface(x1Mesh, x2Mesh, mPost - 2*sPost);
	set(sDown,'FaceAlpha',0.3);
	set(sDown,'LineStyle','none');
	set(sDown,'FaceColor',blue);
	sUp = surface(x1Mesh, x2Mesh, mPost + 2*sPost);
	set(sUp,'FaceAlpha',0.3);
	set(sUp,'LineStyle','none');
	set(sUp,'FaceColor',blue);
	sMid = surface(x1Mesh, x2Mesh, mPost);
	set(sMid,'FaceAlpha',0.8);
	set(sMid,'FaceColor',blue);
	xlabel('h_k');
	ylabel('\alpha_k');
	if outputIndex == 1
		zlabel('h_{k+1}');
	else
		zlabel('\alpha_{k+1}');
	end
	if outputIndex == 1
		view([50,16])
		axis([-h0Range,h0Range,-a0Range,a0Range,-1.5e-2,1e-2]);
	end
	if outputIndex == 2
		view([50,16])
		axis([-h0Range,h0Range,-a0Range,a0Range,-2e-1,2e-1]);
	end

	% We also plot the result from the previous chapter.
	load('../Chapter2/CH2Predictions');
	sPrevious = surface(x1Mesh, x2Mesh, mPostStorage(:,:,outputIndex));
	set(sPrevious,'FaceAlpha',0.5);
	set(sPrevious,'FaceColor',green);
	if exportFigs ~= 0
		export_fig(['NextStatePredictionSEPlusLinear',num2str(outputIndex),'.png'],'-transparent');
	end
end