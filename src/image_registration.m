%%%% Code Overview %%%%%

%%%% Outline of main():
%%%% 1. Extract image patches (as pixel intensity values) and generate labels (as column matrix of 1's and 0's) from raw image data 
%%%%	(comparing given reference points for specific slices)
%%%% 2. Normalize the image intensity values (between 0 and 1)
%%%% 3. Run sample test
%%%%	 Generate training and testing data
%%%%	 Apply each of the 3 models (Multilinear Regression, SRDA, SRKDA)
%%%% 4. Cross-Validation results
%%%%	 Generate accuracy data from cross-validation of dataset
%%%%	 Essentially combination of multiple sample tests
%%%% 5. Create .csv with results

%%%%% Sample Results
%%%%%    (multilinear): auc = 0.5494
%%%%%    SRDA,101 Training, Errorrate: 0.51485  TrainTime: 0.46731  TestTime: 0.0070598
%%%%%    SRKDA,101 Training, Errorrate: 0.37624  TrainTime: 1.9942  TestTime: 0.026137

function main()
	display('Starting image registration');
    echo off;

	% Extract X (patches) and Y (labels) from images first (1:49)
    cant_read = [5;8;25;27;33;36] % list of 'corrupted' image files
    n = 49
	for i=1:n
        if (any(i==cant_read))
            continue
        end
		filename = strcat(int2str(i), '.mat');
		[X,Y] = extractXandY(filename); % Currently extracting flair1, flair3 images (temporal registration)
		if (i == 1)
			X_t = X; % matrix of flair1, flair3 appended
			Y_t = Y; % matrix of 1's, 0's (good match, bad match)
		else
			X_t = [X_t; X];
			Y_t = [Y_t; Y];
		end
    end
    
    %X_unmodified = X_t;
    
    % Pre-processing steps (single example of training-test split applied to 3 given models)

	X_t = NormalizeFea(double(X_t)); % first normalize data

	%every image has 100 windows, so 1:1000 means first ten patients' data
    n_tot = (n - size(cant_read,1)) * 100; % n_tot = 4300

	%set training set and testing set 
	X_train = X_t(1:n_tot - 100,:); % training set from 1:4200 (first 42 patients)
	Y_train = Y_t(1:n_tot - 100,:);
    %X_unmodified_train = X_unmodified(1:n_tot - 100,:);

	X_test = X_t(n_tot-101:n_tot,:); % test set is 43rd patient
	Y_test = Y_t(n_tot-101:n_tot,:);
    %X_unmodified_test = X_unmodified(n_tot-101:n_tot,:);

    %%%%% MULTI-LINEAR MATCHING %%%%%	
    %y threshold for allowing points into RANSAC
    threshold = 0.6;
    b = regress(Y_train, X_train);
    load(strcat(int2str(49), '.mat'));
    img1 = flair1(:,:,ref_flair1); %#ok<NODEF>
    img2 = flair3(:,:,ref_flair3); %#ok<NODEF>
    [pts1, pts2] = findPatches(img1, img2, b, threshold);
    matrix = RANSACmatrix(pts1, pts2, img1, img2, b, threshold);
    display(matrix);
    %imshow?
    
	%%%%% MULTI-LINEAR REGRESSION %%%%%	
	
	multilinear_test(X_train, X_test, Y_train, Y_test);

	%%%%% SPECTRAL REGRESSION %%%%%

	%% SRDA %%

	SRDA_test(X_train, X_test, Y_train, Y_test);


	%% SRKDA %%

	SRKDA_test(X_train, X_test, Y_train, Y_test);


	%%%%% CROSS-VALIDATION TESTING %%%%%

	[a, a_i] = cross_validation(X_t, Y_t, 0)
	[b, b_i] = cross_validation(X_t, Y_t, 1)
	[c, c_i] = cross_validation(X_t, Y_t, 2)
	
	%to test transformation
	% find reference point in one image first, extract a window, and use b to find the other window in the other image that gives near 1 in Y in result.
	% problem now, the other image's windows does not encompass same orientation
	% also, if we just generate transformation matrix using angle, scale and transition, it will be hard to configure these data
	
	fin_results = [a,b,c];
	csvwrite('cv_results_2.csv',fin_results);
	
	% fin_indices = [a_i, b_i, c_i];
	% csvwrite('cv_indices_2.csv',fin_indices);
	
	% findTransformation
    
    

end

function auc = multilinear_test(X_train, X_test, Y_train, Y_test)
	% b is 200 * 1 since we have two corresponding with 100 points each
	%X_t is 4900 * 200
	% we have 100 windows for each image, so 4900 in total
	
	%Y_t is 4900 * 1

	b = calculateRegressionCoefficient(X_train,Y_train);
	auc = AUC_score(X_test, Y_test, b);
end

function accuracy = SRKDA_test(X_train, X_test, Y_train, Y_test)

	%SRKDA

	options = []; 
	options.ReguAlpha = 0.001;  % 0.0001 .001 .01 .1 1 


	fea = X_train;
	fea_test = X_test;

	%X_t is feature matrix, Y_t is label
	tic;
	spec_model = SRKDAtrain(fea, Y_train, options);
	TimeTrain = toc;

	tic;
	accuracy = SRKDApredict(fea_test, Y_test, spec_model); 
	TimeTest = toc;


	[l,m] = size(Y_test);

 	disp(['SRKDA,',num2str(l),' Training, Errorrate: ',num2str(1-accuracy),'  TrainTime: ',num2str(TimeTrain),'  TestTime: ',num2str(TimeTest)]); 
end

function accuracy = SRDA_test(X_train, X_test, Y_train, Y_test)
	%SRDA

	options = []; 
	options.ReguAlpha = 0.001;  % 0.0001 .001 .01 .1 1 


	fea = X_train;
	fea_test = X_test;

	%X_t is feature matrix, Y_t is label
	tic;
	spec_model = SRDAtrain(fea, Y_train, options);
	TimeTrain = toc;

	tic;
	accuracy = SRDApredict(fea_test, Y_test, spec_model); 
	TimeTest = toc;


	[l,m] = size(Y_test);

 	disp(['SRDA,',num2str(l),' Training, Errorrate: ',num2str(1-accuracy),'  TrainTime: ',num2str(TimeTrain),'  TestTime: ',num2str(TimeTest)]); 
end

function b = calculateRegressionCoefficient(X,Y) 
	%{
	[a,b] = size(Y);
	[c,d] = size(X);
	%}
	
	b = regress(Y, X);
end

%%%% Cross-Validation %%%%

function [results, indices] = cross_validation(X_tot, Y_tot, test_type)
	% X_tot consists of entire patch data, Y_tot contains entire label data, k_fold is # of cross-validation sets want to create
	% test_type: 0 for multilinear, 1 for SRDA, 2 for SRKDA
	n = size(X_tot,1);
	k_fold = n / 100; % k_fold fixed in this case, since data organized in 100's
	set_size = n/k_fold;
	tic;
	results = [];
	indices = [];
	for i = 1:k_fold
		% Calculating Testing Subset Indices (based on the set size, which is based off k_fold)
		t_start = (i-1) * set_size + 1;
		t_end = i * set_size;
		indices = vertcat(indices, [t_start,t_end]);
		% Generating Testing Subset: copying based off of indexes
		X_test = X_tot(t_start:t_end,:);
		Y_test = Y_tot(t_start:t_end,:);

		% Generating Training Subset: copy entire array, and then removing testing subset 
		X_train = X_tot;
		Y_train = Y_tot;
		X_train([t_start:t_end], :) = [];
		Y_train([t_start:t_end], :) = [];

		% selecting which test to perform
		if test_type == 0
			a = multilinear_test(X_train, X_test, Y_train, Y_test);
		elseif test_type == 1
			a = SRDA_test(X_train, X_test, Y_train, Y_test);
		else
			a = SRKDA_test(X_train, X_test, Y_train, Y_test);	
		end

		results = vertcat(results, a); %#ok<AGROW>
	end
	time = toc
	disp(results);
end 


%%%% ROC Score Generation %%%%
function auc = AUC_score(X, Y, b) 

	Y_fit = X * b;

	[X_a, Y_a] = roc(Y, Y_fit);
	auc = auroc(X_a, Y_a);

	figure
	plot(X_a,Y_a);
	xlabel('FALSE POSITIVE RATE');
	ylabel('TRUE POSITIVE RATE');
	title('RECEIVER OPERATING CHARACTERISTIC (ROC)');
end

%%% X (patch data) and Y (label data) Extraction from Raw Image %%%
function [X, Y] = extractXandY(filename)
	load(filename);
%     im_1 = flair1;
%     im_2 = flair3;
%     ref_im_1 = ref_flair1
%     ref_im_2 = ref_flair3
    
	display(['processing',' ', filename]);
	%use cp2tform to calculate the 'ground truth' transformation matrix between two reference layers
	t = cp2tform(pt_flair1, pt_flair3, 'affine');

	display(t.tdata.Tinv);

	%use imtrasform/imwarp to transform
	%rFlair1 is the translated image
	rFlair1 =  imtransform(double(flair1(:,:,round(ref_flair1))), t, 'bicubic', 'XData', [1 size(flair3,2)],'YData', [1 size(flair3,1)]);

	% Validating Transform
	%reference points are points that match across images
	%extract 50 random points
	ref_pts = extractPoints(flair3(:,:,round(ref_flair3)));

	%extract patches for each point;
	% 50 patches for each image
	patch_window_f1 = extractPatch(rFlair1, ref_pts(:,2), ref_pts(:,1));
	patch_window_f3 = extractPatch(flair3(:,:,round(ref_flair3)), ref_pts(:,2), ref_pts(:,1));


	display('examining size');

	%10*10*50
	[m,n,l] = size(patch_window_f1);

	%use these points to calculate b in regression
	%making labels for 'good' patch pairs (array of 1's)

	y_good = ones(l, 1);

	x_f1_vec = reshape(patch_window_f1, [m*n,l]);
	x_f3_vec = reshape(patch_window_f3, [m*n,l]);

	% Matching patches

	% 200 * 50

	x_vec_total_good = [x_f1_vec; x_f3_vec];

	[m,n] = size(x_vec_total_good);

	%making labels for 'bad' patch pairs (array of 0's)
	y_bad = zeros(l, 1);

	%retake points and construct windows for bad matches
	ref_pts2 = extractPoints(flair3(:,:,round(ref_flair3)));
    [~,f3width] = size(flair3(:,:,round(ref_flair3)));
    %reroll if the same value is in good values and bad values
    for i=1:50
        while(ref_pts(i,1) == ref_pts2(i,1) && ref_pts(i,2) == ref_pts2(i,2))
            ref_pts(i,1)=randi([30,f3width-30]);
        end
    end
    
	patch_window_f3_bad = extractPatch(flair3(:,:,round(ref_flair3)), ref_pts2(:,2), ref_pts2(:,1));
	[m,n,l] = size(patch_window_f3_bad);

	x_f3_vec_bad = reshape(patch_window_f3_bad, [m*n,l]);

	x_vec_total_bad = [x_f1_vec; x_f3_vec_bad];


	%now we have bad matches

	% total contains 100 patches
	%200 * 100
	x_vec_total = [x_vec_total_good, x_vec_total_bad];
	x_vec_transpose = x_vec_total';

	% 100 labels; 50 good and 50 bad
	y = [y_good; y_bad];

	X = x_vec_transpose;
	Y = y;

end

%%%% Image Patch Extraction %%%%
function [win] = extractPatch(img, pty, ptx)

	winSize = 10; % dim of 'window' used (n by n square)
	x = floor(winSize/2);
	if (mod(winSize, 2) == 1)
		ys = x;
		ye = x;
		xs = x;
		xe = x;
	elseif (mod(winSize, 2) == 0)
		ys = x;
		ye = x-1;
		xs = x;
		xe = x-1;
	end

	numel(pty);
	win = zeros(winSize, winSize, numel(pty), 'single');     

	for i=1:numel(pty)
	    tmp = img(pty(i)-ys:pty(i)+ye, ptx(i)-xs:ptx(i)+xe);
    	norm_tmp = tmp - min(tmp(:));
    	norm_tmp = norm_tmp ./ max(norm_tmp(:));
	    win(:,:,i) = norm_tmp(:,:);
	end

	% figure
	% imshow(win(:,:,1), []);
end

function points = extractPoints(img)
	%extract points from this image
	[m,n] = size(img);

	%randomly pick points
	%to prevent reaching border when building patches, we have 30 as offset
	%50 random points for each image
	points = [randi([30,n-30],1,50); randi([30,m-30],1,50)];
	points = points';
end

function output_pts = filterLowVariation(img, input_pts)
    [amount,~] = size(input_pts);
    patches = extractPatch(img, input_pts(:,2), input_pts(:,1));
    patches = reshape(patches, [100,amount]);
    means = mean(patches);
    minimums = min(patches);
    maximums = max(patches);
    allowed = zeros(1,amount);
    for index=1:amount
       if(maximums(index)-means(index) > 10 && means(index) - minimums(index) > 10)
           allowed(index) = 1;
       end
    end
    output_pts = input_pts(allowed, :);
end

function [pts1, pts2] = findPatches(img1, img2, b, threshold)
    %basically same inputs as RANSAC matrix
    [m1,n1] = size(img1);
    [m2,n2] = size(img2);
    %two lists of random points
    randomlength = 400;
    possible_pts1 = [randi([30,n1-30],1,randomlength); randi([30,m1-30],1,randomlength)];
	possible_pts1 = possible_pts1';
    possible_pts2 = [randi([30,n2-30],1,randomlength); randi([30,m2-30],1,randomlength)];
    possible_pts2 = possible_pts2';
    %exclude patches without variation in intensities
    %possible_pts1 = filterLowVariation(img1, possible_pts1);
    %possible_pts2 = filterLowVariation(img2, possible_pts2);
    %match for best y-value
    [ind1,~] = size(possible_pts1);
    [ind2,~] = size(possible_pts2);
    pts1 = [];
    pts2 = [];
    %find matches between pts1 and pts2 in the images
    for index1=1:ind1
        maxyvalue = 0;
        bestindex = 0;
        patch1 = extractPatch(img1, possible_pts1(ind1,2), possible_pts1(ind1,1));
        %maximum y-value out of the img2 patches
        for index2=1:ind2
            patch2 = extractPatch(img2, possible_pts1(ind2,2), possible_pts1(ind2,1));
            yvalue = [patch1, patch2]*b;
            if(yvalue > maxyvalue)
                bestindex = index2;
                maxyvalue = yvalue;
            end
        end
        %only allow good matches
        if(maxb > threshold)
            pts1 = [pts1;possible_pts1(index1,:)]; %#ok<*AGROW>
            pts2 = [pts2;possible_pts2(bestindex,:)];
        end
    end  
end

function matrix = RANSACmatrix(pts1, pts2, img1, img2, b, threshold)
    %find best transformation matrix using RANSAC on matching patches
    %inputs are x by 2 matrices of patch centers, in image 1 and 2
    %b is weights for multilinear
    %threshold is lowest y-value allowed in RANSAC
    [dim1,~] = size(pts1);
    %amount of times to run loops
    first = 100;
    second = 10;
    times_error = 0;
    %patches from img2
    img2_patches = extractPatch(img2, pts2(:,2), pts2(:,1));
    for i=1:first
        %randomly choose 3 indices of the pt array
        chosen_indices = randperm(dim1,3);
        for j=1:second
            %turn indices into points
            chosen_pts1=pts1(chosen_indices,:);
            chosen_pts2=pts2(chosen_indices,:);
            %cp2transform to find transformation from 3 patches
            try
                found_transform = cp2tform(chosen_pts1, chosen_pts2, 'affine'); %#ok<*DCPTF>
            catch
                %when the points are collinear
                found_matrix = [0 0 0; 0 0 0; 0 0 0];
                times_error = times_error + 1;
                break;
            end
            found_matrix = found_transform.tdata.T;
            %perform transformation
            trans_img1 = imtransform(double(img1), found_transform, 'bicubic', 'XData', [1 size(img1,2)],'YData', [1 size(img1,1)]); %#ok<*DIMTRNS>
            %find transformed patches
            trans_img1_patches = extractPatch(trans_img1, pts1(:,2), pts1(:,1));
            %normalize X for computing Y
            X = [trans_img1_patches, img2_patches];
            X= NormalizeFea(double(X));
            %compute y using b and patches
            y = X*b;
            %find patches which have y > threshold, add centers to the chosen points list
            chosen_indices = [];
            for l = 1:dim1
               if(y(l) > threshold)
                   chosen_indices = [chosen_indices, l]; %#ok<AGROW>
               end
            end
        end
        %add matrix so that it is 3x3 matrix of total element values
        total_transform_matrix = total_transform_matrix + found_matrix;
    end
    %find average matrix
    matrix = total_transform_matrix./(first - times_error);
end


%%%%% ROC functions %%%%%%

function [tp, fp] = roc(t, y)
%
% ROC - generate a receiver operating characteristic curve
%
%    [TP,FP] = ROC(T,Y) gives the true-positive rate (TP) and false positive
%    rate (FP), where Y is a column vector giving the score assigned to each
%    pattern and T indicates the true class (a value above zero represents
%    the positive class and anything else represents the negative class).  To
%    plot the ROC curve,
%
%       PLOT(FP,TP);
%       XLABEL('FALSE POSITIVE RATE');
%       YLABEL('TRUE POSITIVE RATE');
%       TITLE('RECEIVER OPERATING CHARACTERISTIC (ROC)');
%
%    See [1] for further information.
%
%    [1] Fawcett, T., "ROC graphs : Notes and practical
%        considerations for researchers", Technical report, HP
%        Laboratories, MS 1143, 1501 Page Mill Road, Palo Alto
%        CA 94304, USA, April 2004.
%
%    See also : ROCCH, AUROC

%
% File        : roc.m
%
% Date        : Friday 9th June 2005
%
% Author      : Dr Gavin C. Cawley
%
% Description : Generate an ROC curve for a two-class classifier.
%
% References  : [1] Fawcett, T., "ROC graphs : Notes and practical
%                   considerations for researchers", Technical report, HP
%                   Laboratories, MS 1143, 1501 Page Mill Road, Palo Alto
%                   CA 94304, USA, April 2004.
%
% History     : 10/11/2004 - v1.00
%               09/06/2005 - v1.10 - minor recoding
%               05/09/2008 - v2.00 - re-write using algorithm from [1]
%
% Copyright   : (c) G. C. Cawley, September 2008.
%
%    This program is free software; you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation; either version 2 of the License, or
%    (at your option) any later version.
%
%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program; if not, write to the Free Software
%    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
%

ntp = size(y,1);

% sort by classeifier output

[y,idx] = sort(y, 'descend');
t       = t(idx) > 0;

% generate ROC

P     = sum(t);
N     = ntp - P;
fp    = zeros(ntp+2,1);
tp    = zeros(ntp+2,1);
FP    = 0;
TP    = 0;
n     = 1;
yprev = -realmax;

for i=1:ntp

   if y(i) ~= yprev

      tp(n) = TP/P;
      fp(n) = FP/N; 
      yprev = y(i);
      n     = n + 1;

   end

   if t(i) == 1

      TP = TP + 1;

   else

      FP = FP + 1;

   end

end

tp(n) = 1;
fp(n) = 1;
fp    = fp(1:n);
tp    = tp(1:n);

end

function A = auroc(tp, fp)
%
% AUROC - area under ROC curve
%
%    An ROC (receiver operator characteristic) curve is a plot of the true
%    positive rate as a function of the false positive rate of a classifier
%    system.  The area under the ROC curve is a reasonable performance
%    statistic for classifier systems assuming no knowledge of the true ratio
%    of misclassification costs.
%
%    A = AUROC(TP, FP) computes the area under the ROC curve, where TP and FP
%    are column vectors defining the ROC or ROCCH curve of a classifier
%    system.
%
%    [1] Fawcett, T., "ROC graphs : Notes and practical
%        considerations for researchers", Technical report, HP
%        Laboratories, MS 1143, 1501 Page Mill Road, Palo Alto
%        CA 94304, USA, April 2004.
%
%    See also : ROC, ROCCH

%
% File        : auroc.m
%
% Date        : Wednesdaay 11th November 2004 
%
% Author      : Dr Gavin C. Cawley
%
% Description : Calculate the area under the ROC curve for a two-class
%               probabilistic classifier.
%
% References  : [1] Fawcett, T., "ROC graphs : Notes and practical
%                   considerations for researchers", Technical report, HP
%                   Laboratories, MS 1143, 1501 Page Mill Road, Palo Alto
%                   CA 94304, USA, April 2004.
%
% History     : 22/03/2001 - v1.00
%               10/11/2004 - v1.01 minor improvements to comments etc.
%
% Copyright   : (c) G. C. Cawley, November 2004.
%
%    This program is free software; you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation; either version 2 of the License, or
%    (at your option) any later version.
%
%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program; if not, write to the Free Software
%    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
%

n = size(tp, 1);
A = sum((fp(2:n) - fp(1:n-1)).*(tp(2:n)+tp(1:n-1)))/2;

end