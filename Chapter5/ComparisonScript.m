% This file compares many ways of GP regression for noisy input measurements. It compares their performance based on various scenarios.
% 1. Perfect GP regression, with exact input measurements (but noisy output measurements) and exact hyperparameters. (Only 200 measurements.)
% 2. Regular GP regression, with noisy input measurements and tuned hyperparameters. (Only 200 measurements.)
% 3. Regular FITC, using the hyperparameters of (2). (The full 800 measurements.)
% 4. The NIGP algorithm, which tunes the hyperparameters itself. (Only 200 measurements.)
% 5. The SONIG algorithm, using the hyperparameters of (4). (Only 200 measurements.)
% 6. The SONIG algorithm, using the hyperparameters of (4). (The full 800 measurements, which gives a roughly equal runtime as (4).)
% 7. The SONIG algorithm, getting an initial estimate using a subset (100) measurement points of the NIGP algorithm. (A total of 800 measurements are used.)
% Note that this order is different than the one in the paper. It just makes it a bit easier to execute in this order.

% We set up the workspace, ready for executing scripts.
clear all; % Empty the workspace.
clc; % Empty the command window.
exportFigs = 1; % Do we export figures? 0 for no, 1 (or anything else) for yes.
useColor = 1; % Should we set up plots for colored output (1) or black-and-white output (0)?

% We add paths to folder which contain functions we will use.
addpath('../ExportFig');
addpath('../NIGP/');
addpath('../NIGP/util/');
addpath('../NIGP/tprod/');
addpath('../SONIG/');
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

%% We fix Matlab's random number generator, so that it should (in theory) give the same results every run.
rng(1, 'twister');

% We define the range of the plot we will make.
xMin = -5; % What is the minimum x value?
xMax = -xMin; % What is the maximum x value?

% We define numbers of points and set up the corresponding point spaces.
nm = 800; % This is the total number of available measurement points. They are used by algorithms 3, 6 and 7.
nmu = nm/4; % This is the number of measurements used by algorithms 1, 2, 4 and 5.
nmn = nm/8; % This is the number of measurements used for NIGP training in algorithm 7.
ns = 101; % This is the number of plot points.
nu = 21; % The number of inducing input points.
Xs = linspace(xMin,xMax,ns); % These are the plot points.
Xu = linspace(xMin,xMax,nu); % These are the inducing input points.

% We do various experiments. We start looping through them here. We also define some storage parameters.
numIterations = 10; % How many functions do we approximate? For the thesis we used 400. Keep in mind that (at least on my system) one iteration lasts roughly 20 seconds.
numMethods = 7; % How many algorithms do we have? This is 7, unless you add algorithms yourself.
res = zeros(numMethods,3,numIterations);
muuS = zeros(nu,numMethods,numIterations);
musS = zeros(ns,numMethods,numIterations);
SuuS = zeros(nu,nu,numMethods,numIterations);
SssS = zeros(ns,ns,numMethods,numIterations);
XmhS = zeros(nm,numIterations);
XmS = zeros(nm,numIterations);
fmhS = zeros(nm,numIterations);
fmS = zeros(nm,numIterations);
fsS = zeros(ns,numIterations);
counter = 0; % We initialize a counter.
while counter < numIterations
	% We set up some preliminary stuff for the loop.
	counter = counter + 1;
	flag = 0; % This is a flag which checks for problems.
	disp(['Starting loop ',num2str(counter),'.']);

	% We define some settings for the function which we will generate. We generate it by sampling from a GP.
	sfm = 0.1;
	sxm = 0.4;
	lx = 1;
	lf = 1;
	Lambda = lx^2;
	realParams = [lx,sxm,lf,sfm];

	% We set up the input points and the corresponding covariance matrices.
	Xm = xMin + rand(1,nm)*(xMax - xMin); % These are the real measurement input points.
	Xmh = Xm + sxm*randn(1,nm); % These are the input points corrupted by noise.
	XmS(:,counter) = Xm'; % We store the measurement points, in case we want to inspect them later.
	XmhS(:,counter) = Xmh'; % We store the measurement points, in case we want to inspect them later.
	
	% We calculate covariance matrices.
	input = [Xu,Xmh,Xs,Xm];
	diff = repmat(input,[size(input,2),1]) - repmat(input',[1,size(input,2)]);
	K = lf^2*exp(-1/2*diff.^2/Lambda);
	KDivided = mat2cell(K,[nu,nm,ns,nm],[nu,nm,ns,nm]);
	Kuu = KDivided{1,1};
	Kum = KDivided{1,2};
	Kus = KDivided{1,3};
	Kur = KDivided{1,4};
	Kmu = KDivided{2,1};
	Kmm = KDivided{2,2};
	Kms = KDivided{2,3};
	Kmr = KDivided{2,4};
	Ksu = KDivided{3,1};
	Ksm = KDivided{3,2};
	Kss = KDivided{3,3};
	Ksr = KDivided{3,4};
	Kru = KDivided{4,1};
	Krm = KDivided{4,2};
	Krs = KDivided{4,3};
	Krr = KDivided{4,4};

	% To generate a random sample with covariance matrix K, we first have to find the Cholesky decomposition of K. That's what we do here.
	epsilon = 0.0000001; % We add some very small noise to prevent K from being singular.
	L = chol([Krr,Krs;Ksr,Kss] + epsilon*eye(nm+ns))'; % We take the Cholesky decomposition to be able to generate a sample with a distribution according to the right covariance matrix. (Yes, we could also use the mvnrnd function, but that one gives errors more often than the Cholesky function.)
	sample = L*randn(nm+ns,1);

	% We create and store the measurements.
	fm = sample(1:nm)'; % These are the real function measurements, done at the real measurement input points, without any noise.
	fmh = fm + sfm*randn(1,nm); % We add noise to the function measurements, to get the noisy measurements.
	fs = sample(nm+1:nm+ns)'; % This is the function value of the function we want to approximate at the plot points.
	fmS(:,counter) = fm';
	fmhS(:,counter) = fmh';
	fsS(:,counter) = fs';

	% Method 1.
	% We first set up a GP of the true measurements (with output noise but without input noise) with the actual hyperparameters.
	musGPn = Ksr(:,1:nmu)/(Krr(1:nmu,1:nmu) + sfm^2*eye(nmu))*fmh(1:nmu)';
	SssGPn = Kss - Ksr(:,1:nmu)/(Krr(1:nmu,1:nmu) + sfm^2*eye(nmu))*Krs(1:nmu,:);
	stdGPn = sqrt(diag(SssGPn));
	% We examine and store the results.
	musS(:,1,counter) = musGPn;
	SssS(:,:,1,counter) = SssGPn;
	res(1,:,counter) = [mean((musGPn - fs').^2),mean(stdGPn.^2),mean(((musGPn - fs')./stdGPn).^2)];

	% Method 2.
	% We now set up a GP of the noisy measurements, with tuned hyperparameters. First we tune the hyperparameters.
	tic;
	[sfm,lf,Lambda] = tuneHyperparameters(Xmh(1:nmu),fmh(1:nmu)');
	disp(['GP hyperparameter tuning time is ',num2str(toc),' s. Parameters found were lx: ',num2str(sqrt(Lambda)),', lf: ',num2str(lf),', sf: ',num2str(sfm),'.']);
	param2 = [sfm,lf,Lambda];
	% We recalculate covariance matrices.
	input = [Xu,Xmh,Xs,Xm];
	diff = repmat(input,[size(input,2),1]) - repmat(input',[1,size(input,2)]);
	K = lf^2*exp(-1/2*diff.^2/Lambda);
	KDivided = mat2cell(K,[nu,nm,ns,nm],[nu,nm,ns,nm]);
	Kuu = KDivided{1,1};
	Kum = KDivided{1,2};
	Kus = KDivided{1,3};
	Kur = KDivided{1,4};
	Kmu = KDivided{2,1};
	Kmm = KDivided{2,2};
	Kms = KDivided{2,3};
	Kmr = KDivided{2,4};
	Ksu = KDivided{3,1};
	Ksm = KDivided{3,2};
	Kss = KDivided{3,3};
	Ksr = KDivided{3,4};
	Kru = KDivided{4,1};
	Krm = KDivided{4,2};
	Krs = KDivided{4,3};
	Krr = KDivided{4,4};
	% We make a GP prediction using the noisy measurement points.
	musGPm = Ksm(:,1:nmu)/(Kmm(1:nmu,1:nmu) + sfm^2*eye(nmu))*fmh(1:nmu)';
	SssGPm = Kss - Ksm(:,1:nmu)/(Kmm(1:nmu,1:nmu) + sfm^2*eye(nmu))*Kms(1:nmu,:);
	stdGPm = sqrt(diag(SssGPm));
	% We examine and store the results.
	musS(:,2,counter) = musGPm;
	SssS(:,:,2,counter) = SssGPm;
	res(2,:,counter) = [mean((musGPm - fs').^2),mean(stdGPm.^2),mean(((musGPm - fs')./stdGPm).^2)];

	% Method 3.
	% Next, we set up the FITC algorithm for the noisy measurements, using the hyperparameters which we just found. We use all nm measurements here.
	Lmm = diag(diag(Kmm + sfm^2*eye(nm) - Kmu/Kuu*Kum));
	SuuFITC = Kuu/(Kuu + Kum/Lmm*Kmu)*Kuu;
	muuFITC = SuuFITC/Kuu*Kum/Lmm*fmh';
	musFITC = Ksu/Kuu*muuFITC;
	SssFITC = Kss - Ksu/Kuu*(Kuu - SuuFITC)/Kuu*Kus;
	stdsFITC = sqrt(diag(SssFITC));
	% We examine and store the results.
	muuS(:,3,counter) = muuFITC;
	SuuS(:,:,3,counter) = SuuFITC;
	musS(:,3,counter) = musFITC;
	SssS(:,:,3,counter) = SssFITC;
	res(3,:,counter) = [mean((musFITC - fs').^2),mean(stdsFITC.^2),mean(((musFITC - fs')./stdsFITC).^2)];
	
	% Method 4.
	% The next step is to train the NIGP algorithm. We start doing that now. To search more efficiently, we initialize the hyperparameters as the true parameters, but the algorithm won't converge
	% on this anyway. It'll find its own parameters. So no cheating here. Well, not much anyway.
	seard = log(realParams([1,3,4])');
	lsipn = log(realParams(2));
	tic;
	evalc('[model, nigp] = trainNIGP(permute(Xmh(:,1:nmu),[2,1]),permute(fmh(:,1:nmu),[2,1]),-500,1,seard,lsipn);'); % We apply the NIGP training algorithm. We put this in an evalc function to suppress the output made by the NIGP algorithm.
	% We extract the derived settings.
	lx = exp(model.seard(1,1));
	lf = exp(model.seard(2,1));
	sfm = exp(model.seard(3,1));
	sxm = exp(model.lsipn);
	Lambda = lx^2;
	Sxm = sxm^2;
	disp(['NIGP hyperparameter tuning time is ',num2str(toc),' s. Parameters found were lx: ',num2str(lx),', sx: ',num2str(sxm),', lf: ',num2str(lf),', sf: ',num2str(sfm),'.']);
	% We recalculate covariance matrices.
	input = [Xu,Xmh,Xs,Xm];
	diff = repmat(input,[size(input,2),1]) - repmat(input',[1,size(input,2)]);
	K = lf^2*exp(-1/2*diff.^2/Lambda);
	KDivided = mat2cell(K,[nu,nm,ns,nm],[nu,nm,ns,nm]);
	Kuu = KDivided{1,1};
	Kum = KDivided{1,2};
	Kus = KDivided{1,3};
	Kur = KDivided{1,4};
	Kmu = KDivided{2,1};
	Kmm = KDivided{2,2};
	Kms = KDivided{2,3};
	Kmr = KDivided{2,4};
	Ksu = KDivided{3,1};
	Ksm = KDivided{3,2};
	Kss = KDivided{3,3};
	Ksr = KDivided{3,4};
	Kru = KDivided{4,1};
	Krm = KDivided{4,2};
	Krs = KDivided{4,3};
	Krr = KDivided{4,4};
	% We make the NIGP prediction for the test points.
	musNIGP = Ksm(:,1:nmu)/(Kmm(1:nmu,1:nmu) + sfm^2*eye(nmu) + diag(model.dipK(1:nmu)))*fmh(1:nmu)';
	SssNIGP = Kss - Ksm(:,1:nmu)/(Kmm(1:nmu,1:nmu) + sfm^2*eye(nmu) + diag(model.dipK(1:nmu)))*Kms(1:nmu,:);
	stdsNIGP = sqrt(diag(SssNIGP));
	% We examine and store the results.
	musS(:,4,counter) = musNIGP;
	SssS(:,:,4,counter) = SssNIGP;
	res(4,:,counter) = [mean((musNIGP - fs').^2),mean(stdsNIGP.^2),mean(((musNIGP - fs')./stdsNIGP).^2)];

	% Method 5/6/7.
	% And now it's time for the SONIG algorithm, done in various ways.
	for method = 5:7
		% We first look at which measurements we use, as well as set up a SONIG object and give it the right inducing input points.
		if method == 5 || method == 6
			% We set which measurement points we will use.
			fromPoint = 1;
			if method == 5
				toPoint = nmu;
			else
				toPoint = nm;
			end
			% We set up a SONIG object with the right hyperparameters.
			hyp = NIGPModelToHyperparameters(model);
			sonig = createSONIG(hyp);
			sonig = addInducingInputPoint(sonig, Xu);
		else
			% We set which measurement points we will use.
			fromPoint = nmn+1;
			toPoint = nm;
			% We apply NIGP training on the first set of measurements.
			seard = log(realParams([1,3,4])');
			lsipn = log(realParams(2));
			tic;
			evalc('[model, nigp] = trainNIGP(permute(Xmh(:,1:nmn),[2,1]),permute(fmh(:,1:nmn),[2,1]),-500,1,seard,lsipn);'); % We apply the NIGP training algorithm. We put this in an evalc function to suppress the output made by the NIGP algorithm.
			% We extract the derived settings.
			lx = exp(model.seard(1,1));
			lf = exp(model.seard(2,1));
			sfm = exp(model.seard(3,1));
			sxm = exp(model.lsipn);
			Lambda = lx^2;
			Sxm = sxm^2;
			% We recalculate covariance matrices.
			input = [Xu,Xmh,Xs,Xm];
			diff = repmat(input,[size(input,2),1]) - repmat(input',[1,size(input,2)]);
			K = lf^2*exp(-1/2*diff.^2/Lambda);
			Kuu = K(1:nu,1:nu);
			Kmu = K(nu+1:nu+nm,1:nu);
			Ksu = K(nu+nm+1:nu+nm+ns,1:nu);
			Kru = K(nu+nm+ns+1:nu+nm+ns+nm,1:nu);
			Kum = K(1:nu,nu+1:nu+nm);
			Kmm = K(nu+1:nu+nm,nu+1:nu+nm);
			Ksm = K(nu+nm+1:nu+nm+ns,nu+1:nu+nm);
			Krm = K(nu+nm+ns+1:nu+nm+ns+nm,nu+1:nu+nm);
			Kus = K(1:nu,nu+nm+1:nu+nm+ns);
			Kms = K(nu+1:nu+nm,nu+nm+1:nu+nm+ns);
			Kss = K(nu+nm+1:nu+nm+ns,nu+nm+1:nu+nm+ns);
			Krs = K(nu+nm+ns+1:nu+nm+ns+nm,nu+nm+1:nu+nm+ns);
			Kur = K(1:nu,nu+nm+ns+1:nu+nm+ns+nm);
			Kmr = K(nu+1:nu+nm,nu+nm+ns+1:nu+nm+ns+nm);
			Ksr = K(nu+nm+1:nu+nm+ns,nu+nm+ns+1:nu+nm+ns+nm);
			Krr = K(nu+nm+ns+1:nu+nm+ns+nm,nu+nm+ns+1:nu+nm+ns+nm);
			% We set up a SONIG object and give it the starting distribution given by the NIGP algorithm.
			hyp = NIGPModelToHyperparameters(model); % We use the hyperparameters just provided by the NIGP algorithm.
			sonig = createSONIG(hyp);
			sonig = addInducingInputPoint(sonig, Xu);
			muu = Kum(:,1:nmn)/(Kmm(1:nmn,1:nmn) + sfm^2*eye(nmn) + diag(model.dipK(1:nmn)))*fmh(1:nmn)'; % This is the mean of the inducing input points, predicted by NIGP after nmn measurements.
			Suu = Kuu - Kum(:,1:nmn)/(Kmm(1:nmn,1:nmn) + sfm^2*eye(nmn) + diag(model.dipK(1:nmn)))*Kmu(1:nmn,:); % And this is the covariance matrix.
			sonig.fu{1} = createDistribution(muu, Suu);
		end
		
		% And now we implement all the measurements into the SONIG object.
		for i = fromPoint:toPoint
			inputDist = createDistribution(Xmh(:,i), hyp.sx^2); % This is the prior distribution of the input point.
			outputDist = createDistribution(fmh(:,i), hyp.sy^2); % This is the prior distribution of the output point.
			[sonig, inputPost, outputPost] = implementMeasurement(sonig, inputDist, outputDist); % We implement the measurement into the SONIG object.
		end
		[musSONIG, SssSONIG, stdsSONIG] = makeSonigPrediction(sonig, Xs); % Here we make the prediction.
		
		% We check if the resulting SONIG object is valid. If not, some problem has occurred.
		if sonig.valid == 0
			disp(['Problems occurred. Restarting loop ',num2str(counter),'.']);
			counter = counter - 1;
			continue;
		end
		
		% We examine and store the results.
		muuS(:,method,counter) = sonig.fu{1}.mean;
		SuuS(:,:,method,counter) = sonig.fu{1}.cov;
		musS(:,method,counter) = musSONIG;
		SssS(:,:,method,counter) = SssSONIG;
		res(method,:,counter) = [mean((musSONIG - fs').^2),mean(stdsSONIG.^2),mean(((musSONIG - fs')./stdsSONIG).^2)];
	end
end

% Finally, we evaluate the results. For this, we get rid of the worst parts of the results of each algorithm.
disp('We are done! Results are as follows for the various methods. (Note that the order is different from the order in the paper.)');
disp('	MSE		Mean var.	Ratio	(The MSE and Mean var have been multiplied by 1000 for visibility.)');
partUsed = 0.9; % Which part of the measurements do we use? (The remainder, being the worst experiments, will be thrown out.)
resSorted = sort(res, 3, 'ascend'); % We sort all the results, so that it becomes easy to select the best 90%.
result = mean(resSorted(:,1:2,1:partUsed*numIterations),3);
disp([result*1e3,result(:,1)./result(:,2)]); % We show the results. We multiply the errors by a thousand to make the numbers more visible in Matlab.

% save('ComparisonScript400Experiments');

%% With this script, we can plot the result of a certain sample from the script above. We can also load in earlier data.

% load('ComparisonScript400Experiments');

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

% Which sample (or counter number) should we plot?
sample = 1;

% We extract the measurements and plot points for this case.
Xmh = XmhS(:,sample);
Xm = XmS(:,sample);
fmh = fmhS(:,sample);
fm = fmS(:,sample);
fs = fsS(:,sample);

% We plot the resulting function generated for that case, including the measurements that were done.
figure(11);
clf(11);
hold on;
grid on;
plot(Xs, fs, 'b-'); % This is the true function which we are approximating.
plot(Xm(1:nmu), fm(1:nmu), 'g+'); % These are the measurements without noise.
plot(Xmh(1:nmu), fmh(1:nmu), 'ro'); % These are the actual noisy measurements.
xlabel('Input');
ylabel('Output');

% For each of the algorithms, we plot the results.
pointsUsed = [nmu,nmu,nm,nmu,nmu,nm,nm];
plotMin = floor(min(fmh)*2)/2;
plotMax = ceil(max(fmh)*2)/2;
caseTranslation = [1,2,7,3,4,5,6]; % This is the translation vector from the case numbers in this script to the case numbers in the thesis.
for i = 1:numMethods
	muu = muuS(:,i,sample);
	stdu = sqrt(diag(SuuS(:,:,i,sample)));
	mus = musS(:,i,sample);
	stds = sqrt(diag(SssS(:,:,i,sample)));
	figure(i);
	clf(i);
	hold on;
	grid on;
	xlabel('Input');
	ylabel('Output');
	patch([Xs, fliplr(Xs)],[mus-2*stds; flipud(mus+2*stds)], 1, 'FaceColor', (grey+white)/2, 'EdgeColor', 'none'); % This is the grey area in the plot.
	patch([Xs, fliplr(Xs)],[mus-stds; flipud(mus+stds)], 1, 'FaceColor', grey, 'EdgeColor', 'none'); % This is the grey area in the plot.
	set(gca, 'layer', 'top'); % We make sure that the grid lines and axes are above the grey area.
	plot(Xs, mus, '-', 'LineWidth', 1, 'Color', blue); % We plot the mean line.
	if i == 1
		plot(Xm(1:pointsUsed(i)), fmh(1:pointsUsed(i)), 'o', 'Color', red);
	else
		plot(Xmh(1:pointsUsed(i)), fmh(1:pointsUsed(i)), 'o', 'Color', red);
	end
	plot(Xs, fs, '-', 'Color', black);
	if muuS(1,i,sample) ~= 0
		errorbar(Xu, muu, 2*stdu, '*', 'Color', yellow); % We plot the inducing input points.
	end
	axis([xMin,xMax,plotMin,plotMax]);
	if exportFigs ~= 0
		export_fig(['ComparisonSampleForScriptCase',num2str(i),'.png'],'-transparent');
		export_fig(['ComparisonSampleCase',num2str(caseTranslation(i)),'.png'],'-transparent');
	end
end